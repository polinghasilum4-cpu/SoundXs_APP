import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/track.dart';
import 'api_service.dart';

enum DlStatus { queued, running, paused, done, failed }

class DlItem {
  DlItem(this.track, {this.status = DlStatus.queued});

  Track track;
  DlStatus status;
  int received = 0;
  int total = 0; // 0 = ukuran belum diketahui
  double speed = 0; // byte/detik
  String? error;
  String? audioPath; // file final
  String? coverPath;
  int sizeBytes = 0;
  DateTime addedAt = DateTime.now();

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'audio': audioPath,
        'cover': coverPath,
        'size': sizeBytes,
        'at': addedAt.millisecondsSinceEpoch,
      };
}

/// Notifier per-lagu supaya tombol unduh di tiap baris hanya rebuild saat lagunya berubah.
class _IdNotifier extends ChangeNotifier {
  void poke() => notifyListeners();
}

class _Ctl {
  StreamSubscription<List<int>>? sub;
  Completer<void>? done;
  DlStatus? stopAs; // paused / null (batal)
  bool canceled = false;
}

/// Unduhan offline.
///  - File disimpan di penyimpanan privat aplikasi (tanpa izin storage).
///  - Hanya lagu yang ditandai `downloadable == true` oleh penyedia dan bukan HLS.
///  - Index disimpan di JSON permanen; file yang hilang otomatis dibuang dari index.
class DownloadManager extends ChangeNotifier {
  static const _maxParallel = 2;
  static const _ua = 'Mozilla/5.0 (Linux; Android 13) SoundXs';

  final ApiService _api = ApiService();
  final http.Client _http = http.Client();
  final Map<String, DlItem> _items = {};
  final Map<String, _Ctl> _ctl = {};
  final Map<String, _IdNotifier> _watchers = {};

  Directory? _dir;
  File? _index;
  bool _loaded = false;
  Timer? _tick;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  // ───────────── Inisialisasi ─────────────
  Future<void> load() async {
    if (_loaded) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/downloads');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dir = dir;
      final idx = _index = File('${dir.path}/index.json');
      if (await idx.exists()) {
        final raw = jsonDecode(await idx.readAsString());
        if (raw is List) {
          for (final e in raw) {
            if (e is! Map) continue;
            final m = Map<String, dynamic>.from(e);
            final tj = m['track'];
            if (tj is! Map) continue;
            final t = Track.fromJson(Map<String, dynamic>.from(tj));
            final path = m['audio']?.toString();
            if (t.id.isEmpty || path == null || !await File(path).exists()) continue;
            final it = DlItem(t, status: DlStatus.done)
              ..audioPath = path
              ..coverPath = m['cover']?.toString()
              ..sizeBytes = (m['size'] as num?)?.toInt() ?? 0
              ..addedAt = DateTime.fromMillisecondsSinceEpoch((m['at'] as num?)?.toInt() ?? 0);
            it.received = it.total = it.sizeBytes;
            _items[t.id] = it;
          }
        }
      }
      // buang sisa file .part yatim
      await for (final f in dir.list()) {
        if (f is File && f.path.endsWith('.part') && !_items.values.any((e) => '${e.audioPath}.part' == f.path)) {
          // .part milik unduhan yang belum selesai tidak ada di index -> aman dihapus saat start
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('DownloadManager.load error: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  // ───────────── Query ─────────────
  List<DlItem> get all => _items.values.toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));
  List<DlItem> get completed => all.where((e) => e.status == DlStatus.done).toList();
  List<DlItem> get active => all.where((e) => e.status != DlStatus.done).toList();
  DlItem? itemFor(String id) => _items[id];
  bool isDone(String id) => _items[id]?.status == DlStatus.done;
  int get totalBytes => completed.fold(0, (a, e) => a + e.sizeBytes);

  String? localAudio(String id) {
    final it = _items[id];
    if (it == null || it.status != DlStatus.done) return null;
    return it.audioPath;
  }

  String? localCover(String id) {
    final p = _items[id]?.coverPath;
    return p != null && File(p).existsSync() ? p : null;
  }

  Listenable watch(String id) => _watchers.putIfAbsent(id, _IdNotifier.new);

  /// null = boleh diunduh. Selain itu = alasan yang ditampilkan ke pengguna.
  String? blockReason(Track t) {
    if (t.kind != ItemKind.track) return 'Hanya lagu yang bisa diunduh.';
    if (isDone(t.id)) return null;
    if (t.streamType == 'hls') {
      return 'Lagu ini hanya tersedia sebagai stream HLS (potongan-potongan), jadi tidak bisa disimpan sebagai satu file.';
    }
    if (t.downloadable != true) {
      return 'Penyedia lagu ini tidak menandainya boleh diunduh. Lagu tetap bisa diputar lewat streaming.';
    }
    return null;
  }

  // ───────────── Antrian ─────────────
  /// Mengembalikan alasan penolakan, atau null jika berhasil masuk antrian / sudah ada.
  String? enqueue(Track t) {
    final reason = blockReason(t);
    if (reason != null) return reason;
    final dir = _dir;
    if (dir == null) return 'Penyimpanan belum siap, coba lagi sebentar.';

    final existing = _items[t.id];
    if (existing != null) {
      if (existing.status == DlStatus.failed || existing.status == DlStatus.paused) resume(t.id);
      return null; // sudah selesai / sedang berjalan -> tidak diunduh ulang
    }
    final it = DlItem(t);
    it.audioPath = '${dir.path}/${_safe(t.id)}.mp3';
    _items[t.id] = it;
    _changed(t.id);
    _pump();
    return null;
  }

  int enqueueAll(List<Track> tracks) {
    var ok = 0;
    for (final t in tracks) {
      if (t.kind == ItemKind.track && enqueue(t) == null && !isDone(t.id)) ok++;
    }
    return ok;
  }

  void pause(String id) {
    final it = _items[id];
    final c = _ctl[id];
    if (it == null) return;
    if (it.status == DlStatus.running && c != null) {
      c.stopAs = DlStatus.paused;
      c.sub?.cancel();
      if (c.done != null && !c.done!.isCompleted) c.done!.complete();
    } else if (it.status == DlStatus.queued) {
      it.status = DlStatus.paused;
      _changed(id);
    }
  }

  void resume(String id) {
    final it = _items[id];
    if (it == null) return;
    if (it.status == DlStatus.paused || it.status == DlStatus.failed) {
      it.status = DlStatus.queued;
      it.error = null;
      _changed(id);
      _pump();
    }
  }

  void retry(String id) => resume(id);

  Future<void> cancel(String id) async {
    final it = _items[id];
    if (it == null || it.status == DlStatus.done) return;
    final c = _ctl[id];
    if (c != null && it.status == DlStatus.running) {
      c.canceled = true;
      c.sub?.cancel();
      if (c.done != null && !c.done!.isCompleted) c.done!.complete();
      return; // _run yang membersihkan
    }
    _items.remove(id);
    await _deletePart(it);
    _changed(id);
  }

  Future<void> remove(String id) async {
    final it = _items.remove(id);
    if (it == null) return;
    await _deleteFiles(it);
    await _saveIndex();
    _changed(id);
  }

  Future<void> removeAll() async {
    for (final id in _items.keys.toList()) {
      final it = _items[id]!;
      if (it.status == DlStatus.running) {
        _ctl[id]?.canceled = true;
        _ctl[id]?.sub?.cancel();
        final d = _ctl[id]?.done;
        if (d != null && !d.isCompleted) d.complete();
      }
      _items.remove(id);
      await _deleteFiles(it);
      _changed(id);
    }
    await _saveIndex();
  }

  // ───────────── Mesin unduh ─────────────
  void _pump() {
    final running = _items.values.where((e) => e.status == DlStatus.running).length;
    var slots = _maxParallel - running;
    if (slots <= 0) return;
    for (final it in _items.values.toList()) {
      if (slots <= 0) break;
      if (it.status == DlStatus.queued && !_ctl.containsKey(it.track.id)) {
        slots--;
        it.status = DlStatus.running;
        _changed(it.track.id);
        unawaited(_run(it));
      }
    }
  }

  Future<void> _run(DlItem it) async {
    final id = it.track.id;
    final ctl = _ctl[id] = _Ctl();
    _startTick();
    IOSink? sink;
    final path = it.audioPath!;
    final part = File('$path.part');
    try {
      var src = it.track;
      if (!src.hasStream) {
        final fresh = await _api.refresh(src);
        if (fresh == null) throw const HttpException('Data lagu tidak ditemukan');
        src = fresh;
      }
      // Cek ulang izin pada data terbaru (jangan percaya data lama).
      if (src.downloadable == false) throw const HttpException('Penyedia tidak mengizinkan unduhan');

      var offset = await part.exists() ? await part.length() : 0;
      final url = await _api.proxiedStream(src);
      if (url.isEmpty) throw const HttpException('URL stream kosong');

      final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = _ua;
      if (offset > 0) req.headers['Range'] = 'bytes=$offset-';
      final resp = await _http.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        throw HttpException('Server menjawab ${resp.statusCode}');
      }
      final ct = (resp.headers['content-type'] ?? '').toLowerCase();
      if (ct.contains('mpegurl') || ct.contains('json') || ct.startsWith('text/')) {
        throw const HttpException('Format stream tidak bisa disimpan');
      }
      final append = resp.statusCode == 206 && offset > 0;
      if (!append) offset = 0;
      it.received = offset;
      it.total = resp.contentLength != null ? resp.contentLength! + offset : 0;

      sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
      final done = ctl.done = Completer<void>();
      var lastBytes = it.received;
      var lastAt = DateTime.now();
      ctl.sub = resp.stream.listen(
        (chunk) {
          sink!.add(chunk);
          it.received += chunk.length;
          final now = DateTime.now();
          final dt = now.difference(lastAt).inMilliseconds;
          if (dt >= 1000) {
            it.speed = (it.received - lastBytes) * 1000 / dt;
            lastBytes = it.received;
            lastAt = now;
          }
          _softNotify(id);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        onError: (Object e, StackTrace st) {
          if (!done.isCompleted) done.completeError(e, st);
        },
        cancelOnError: true,
      );
      await done.future;
      await sink?.flush();
      await sink?.close();
      sink = null;

      if (ctl.canceled) {
        await _deletePart(it);
        _items.remove(id);
        return;
      }
      if (ctl.stopAs == DlStatus.paused) {
        it.status = DlStatus.paused;
        it.speed = 0;
        return;
      }
      final size = await part.length();
      if (size < 1024 || (it.total > 0 && size < it.total)) {
        throw const HttpException('File tidak lengkap');
      }
      final target = File(path);
      if (await target.exists()) await target.delete();
      await part.rename(path);
      it.sizeBytes = size;
      it.received = it.total = size;
      it.speed = 0;
      it.status = DlStatus.done;
      it.addedAt = DateTime.now();
      it.coverPath = await _saveCover(it.track);
      await _saveIndex();
    } catch (e) {
      try {
        await sink?.close();
      } catch (_) {}
      if (ctl.canceled) {
        await _deletePart(it);
        _items.remove(id);
      } else if (ctl.stopAs == DlStatus.paused) {
        it.status = DlStatus.paused;
      } else {
        it.status = DlStatus.failed;
        it.speed = 0;
        it.error = _friendly(e);
      }
    } finally {
      _ctl.remove(id);
      _changed(id);
      _pump();
      if (_ctl.isEmpty) _stopTick();
    }
  }

  Future<String?> _saveCover(Track t) async {
    final dir = _dir;
    if (dir == null || t.coverUrl.isEmpty) return null;
    try {
      final res = await _http.get(Uri.parse(t.coverUrl), headers: {'User-Agent': _ua}).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      final f = File('${dir.path}/${_safe(t.id)}.cover');
      await f.writeAsBytes(res.bodyBytes, flush: true);
      return f.path;
    } catch (_) {
      return null; // cover gagal tidak membatalkan unduhan lagu
    }
  }

  String _friendly(Object e) {
    if (e is SocketException || e is http.ClientException) return 'Koneksi terputus';
    if (e is TimeoutException) return 'Koneksi lambat (timeout)';
    if (e is HttpException) return e.message;
    return 'Unduhan gagal';
  }

  // ───────────── Util ─────────────
  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  Future<void> _deletePart(DlItem it) async {
    final p = it.audioPath;
    if (p == null) return;
    try {
      final f = File('$p.part');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> _deleteFiles(DlItem it) async {
    await _deletePart(it);
    for (final p in [it.audioPath, it.coverPath]) {
      if (p == null) continue;
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _saveIndex() async {
    final f = _index;
    if (f == null) return;
    try {
      final data = jsonEncode(_items.values.where((e) => e.status == DlStatus.done).map((e) => e.toJson()).toList());
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path); // tulis atomik -> index tidak rusak kalau app mati mendadak
    } catch (e) {
      debugPrint('DownloadManager save error: $e');
    }
  }

  void _softNotify(String id) {
    final now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 250) return;
    _lastNotify = now;
    _watchers[id]?.poke();
    notifyListeners();
  }

  void _changed(String id) {
    _watchers[id]?.poke();
    notifyListeners();
  }

  // Menjaga kecepatan tampil 0 saat macet.
  void _startTick() {
    _tick ??= Timer.periodic(const Duration(seconds: 2), (_) {
      var any = false;
      for (final it in _items.values) {
        if (it.status == DlStatus.running) any = true;
      }
      if (!any) _stopTick();
    });
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  @override
  void dispose() {
    _stopTick();
    _http.close();
    super.dispose();
  }
}

String fmtBytes(num b) {
  if (b < 1024) return '${b.toInt()} B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
  return '${(b / 1073741824).toStringAsFixed(2)} GB';
}
