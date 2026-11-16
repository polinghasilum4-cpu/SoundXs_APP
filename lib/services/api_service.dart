import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/track.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Satu baris lirik. startMs/endMs dalam milidetik. startMs = -1 kalau lirik tidak tersinkron.
class LyricLine {
  final double startMs;
  final double? endMs;
  final String text;
  const LyricLine({required this.startMs, this.endMs, required this.text});
}

class LyricsResult {
  final List<LyricLine> lines;
  final bool synced;
  const LyricsResult(this.lines, this.synced);
  bool get isEmpty => lines.isEmpty;
}

typedef _LyricCand = ({String title, String artist});

class _Cached {
  final List<Track> items;
  final DateTime at = DateTime.now();
  _Cached(this.items);
}

/// Singleton: `ApiService()` selalu mengembalikan instance yang sama,
/// jadi cache, client HTTP, dan client_id dipakai bersama semua layar.
class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  static const _api = '/api';
  // Per percobaan. Cold start Vercel biasanya selesai di bawah ini; kalau belum, retry.
  static const _timeout = Duration(seconds: 12);
  static const _ttl = Duration(minutes: 5);

  static const _credKey = 'sc_client_id';
  static const _credAtKey = 'sc_client_id_at';
  static const _credTtlMs = 12 * 60 * 60 * 1000;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; SM-A135F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static final _lrcLine = RegExp(r'^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)$');
  static final _emoji = RegExp(r'[\u{10000}-\u{10FFFF}\u2600-\u27BF\uFE0F\u200D]', unicode: true);
  static final _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]');
  static final _noise = RegExp(
    r'(?i)\b(official|lyrics?|audio|video|mv|hd|hq|viral|tiktok|spotify|music|lagu|terbaru|hits?|pop indonesia|indonesia)\b',
  );
  static final _year = RegExp(r'\b20[0-3][0-9]\b');
  static final _space = RegExp(r'\s+');
  static final _sep = RegExp(r'[|_~•·]+');

  final http.Client _http = http.Client();
  final Map<String, _Cached> _cache = {};
  final Map<String, Future<List<Track>>> _inflight = {};
  String? _clientId;
  Future<String>? _credFuture;

  /// Dipanggil saat app start: client_id siap sebelum Beranda minta data.
  Future<void> warmUp() async {
    try {
      await getCredentials();
    } catch (_) {}
  }

  Future<dynamic> _getJson(
    Uri uri, {
    void Function(int status)? onStatus,
    Duration? timeout,
    int retries = 3,
  }) async {
    ApiException? last;
    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        final res = await _http
            .get(uri, headers: {'Accept': 'application/json', 'User-Agent': _ua})
            .timeout(timeout ?? _timeout);
        onStatus?.call(res.statusCode);
        dynamic data;
        try {
          data = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          data = null;
        }
        if (res.statusCode == 200) return data;
        final msg = data is Map ? data['error'] : null;
        last = ApiException(msg?.toString() ?? 'Server error (${res.statusCode})');
        final retryable = res.statusCode >= 500 || res.statusCode == 429;
        if (!retryable) throw last;
      } on TimeoutException {
        last = ApiException('Server lambat, coba lagi.');
      } on SocketException {
        last = ApiException('Tidak ada koneksi internet.');
      } on http.ClientException {
        last = ApiException('Tidak ada koneksi internet.');
      }
      if (attempt < retries) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    throw last ?? ApiException('Koneksi gagal.');
  }

  /// client_id disimpan di perangkat (12 jam). Permintaan bersamaan berbagi satu future.
  Future<String> getCredentials({bool force = false}) {
    if (!force && _clientId != null) return Future.value(_clientId);
    final running = _credFuture;
    if (!force && running != null) return running;
    final f = _loadCredentials(force);
    _credFuture = f;
    return f.whenComplete(() {
      if (identical(_credFuture, f)) _credFuture = null;
    });
  }

  Future<String> _loadCredentials(bool force) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final saved = prefs.getString(_credKey);
      final at = prefs.getInt(_credAtKey) ?? 0;
      if (saved != null &&
          saved.length >= 20 &&
          DateTime.now().millisecondsSinceEpoch - at < _credTtlMs) {
        _clientId = saved;
        return saved;
      }
    }
    final data = await _getJson(Uri.parse('${ApiConfig.baseUrl}$_api/get-credentials'));
    final id = data is Map ? (data['client_id'] ?? data['clientId']) : null;
    if (id is! String || id.length < 20) {
      throw ApiException('Kredensial SoundCloud tidak tersedia');
    }
    _clientId = id;
    await prefs.setString(_credKey, id);
    await prefs.setInt(_credAtKey, DateTime.now().millisecondsSinceEpoch);
    return id;
  }

  Future<List<Track>> _requestSearch(Map<String, String> params, ItemKind kind) {
    final keys = params.keys.toList()..sort();
    final key = keys.map((k) => '$k=${params[k]}').join('&');

    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _ttl) {
      return Future.value(hit.items);
    }
    final running = _inflight[key];
    if (running != null) return running;

    final f = _fetchSearch(params, kind).then((items) {
      // Hasil kosong tidak di-cache, supaya percobaan berikutnya benar-benar mengambil data baru.
      if (items.isNotEmpty) {
        _cache[key] = _Cached(items);
        if (_cache.length > 40) _cache.remove(_cache.keys.first);
      }
      return items;
    }).whenComplete(() => _inflight.remove(key));
    _inflight[key] = f;
    return f;
  }

  /// Backend bisa membungkus daftar di collection/tracks/results/data. Ambil list-nya.
  List<dynamic>? _unwrapList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return null;
    for (final key in const ['collection', 'tracks', 'results', 'data']) {
      final c = data[key];
      if (c is List) return c;
      if (c is Map) {
        for (final nk in const ['collection', 'tracks', 'results']) {
          final n = c[nk];
          if (n is List) return n;
        }
      }
    }
    return null;
  }

  Future<List<Track>> _fetchSearch(Map<String, String> params, ItemKind kind) async {
    Uri build(String clientId) => Uri.parse('${ApiConfig.baseUrl}$_api/search')
        .replace(queryParameters: {...params, 'client_id': clientId});

    dynamic data;
    var status = 200;
    try {
      data = await _getJson(build(await getCredentials()), onStatus: (s) => status = s);
    } on ApiException {
      if (status != 401) rethrow;
      // client_id kedaluwarsa: ambil yang baru sekali, lalu coba lagi.
      data = await _getJson(build(await getCredentials(force: true)));
    }

    if (data is Map && data['success'] == false) {
      throw ApiException(data['error']?.toString() ?? 'Request gagal');
    }
    final list = _unwrapList(data);
    if (list == null) throw ApiException('Format data tidak dikenali');

    final out = <Track>[];
    for (final e in list) {
      if (e is! Map) continue;
      final t = Track.fromJson(Map<String, dynamic>.from(e), kind: kind);
      if (t.id.isNotEmpty) out.add(t);
    }
    return out;
  }

  Future<List<Track>> search(String q) =>
      _requestSearch({'q': q.trim(), 'type': 'tracks'}, ItemKind.track);
  Future<List<Track>> searchPlaylists(String q) =>
      _requestSearch({'q': q.trim(), 'type': 'playlists'}, ItemKind.playlist);
  Future<List<Track>> searchArtists(String q) =>
      _requestSearch({'q': q.trim(), 'type': 'users'}, ItemKind.user);

  Future<List<Track>> getPlaylistTracks(String id) =>
      // Minta batas maksimum agar playlist tidak terpotong menjadi beberapa lagu.
      _requestSearch({'playlist_id': id, 'type': 'tracks', 'limit': '200'}, ItemKind.track);

  /// Lagu milik artis. Coba berdasarkan user_id dulu; kalau backend tidak mendukungnya,
  /// jatuh ke pencarian nama artis dan menyaring lagu yang benar-benar dari artis itu.
  Future<List<Track>> getArtistTracks(Track artist) async {
    try {
      final byId = await _requestSearch(
        {'user_id': artist.id, 'type': 'tracks', 'limit': '200'},
        ItemKind.track,
      );
      if (byId.isNotEmpty) return byId;
    } catch (_) {}
    final name = artist.title.trim().toLowerCase();
    final byName = await search(artist.title);
    final own = byName.where((e) => e.artist.trim().toLowerCase() == name).toList();
    return own.isNotEmpty ? own : byName;
  }

  /// URL stream lewat proxy server (sama seperti versi web):
  /// /api/stream?url=<stream_url SoundCloud>&client_id=...&track_authorization=...
  Future<String> proxiedStream(Track t) async {
    if (t.streamUrl.isEmpty) return '';
    final id = await getCredentials();
    return Uri.parse('${ApiConfig.baseUrl}$_api/stream').replace(queryParameters: {
      'url': t.streamUrl,
      'client_id': id,
      if (t.trackAuthorization.isNotEmpty) 'track_authorization': t.trackAuthorization,
    }).toString();
  }

  /// Ambil data lagu terbaru (stream_url + track_authorization) untuk lagu yang sudah kedaluwarsa.
  Future<Track?> refresh(Track t) async {
    final list = await search('${t.title} ${t.artist}');
    for (final e in list) {
      if (e.id == t.id && e.streamUrl.isNotEmpty) return e;
    }
    final byTitle = await search(t.title);
    for (final e in byTitle) {
      if (e.id == t.id && e.streamUrl.isNotEmpty) return e;
    }
    return null;
  }

  static String _collapse(String s) => s.replaceAll(_space, ' ').trim();

  /// Bersihkan judul SoundCloud (emoji, tag viral, tahun, kurung).
  static String cleanTitle(String raw) {
    var s = raw.replaceAll(_emoji, ' ');
    s = s.replaceAll(_brackets, ' ');
    s = s.replaceAll(_noise, ' ');
    s = s.replaceAll(_year, ' ');
    s = s.replaceAll(_sep, ' ');
    return _collapse(s);
  }

  static String cleanArtist(String raw) => _collapse(raw.replaceAll(_emoji, ' '));

  /// Kandidat (judul, artis) untuk pencarian lirik. Judul SoundCloud sering berbentuk
  /// "Judul - Artis" atau "Artis - Judul", dan uploader belum tentu artisnya.
  List<_LyricCand> _lyricCandidates(Track t) {
    final out = <_LyricCand>[];
    void add(String title, String artist) {
      final ti = title.trim();
      final ar = artist.trim();
      if (ti.length < 2) return;
      final dup = out.any((c) =>
          c.title.toLowerCase() == ti.toLowerCase() && c.artist.toLowerCase() == ar.toLowerCase());
      if (!dup) out.add((title: ti, artist: ar));
    }

    final uploader = cleanArtist(t.artist);
    final raw = t.title;
    if (raw.contains(' - ')) {
      final parts = raw.split(' - ');
      final left = cleanTitle(parts.first);
      final right = cleanTitle(parts.sublist(1).join(' - '));
      add(left, right);
      add(right, left);
    }
    add(cleanTitle(raw), uploader);
    add(cleanTitle(raw), '');
    return out.take(4).toList();
  }

  Future<LyricsResult?> _lyricsFromBackend(_LyricCand c, int? duration) async {
    try {
      final data = await _getJson(
        Uri.parse('${ApiConfig.baseUrl}$_api/lyrics').replace(queryParameters: {
          'title': c.title,
          if (c.artist.isNotEmpty) 'artist': c.artist,
          if (duration != null) 'duration': '$duration',
        }),
        timeout: const Duration(seconds: 6),
        retries: 1,
      );
      if (data is! Map || data['success'] != true) return null;
      final raw = data['lines'];
      if (raw is! List || raw.isEmpty) return null;
      final wantSynced = data['synced'] == true;
      final out = <LyricLine>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final text = (e['text'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        final tSec = e['t'];
        final endSec = e['end'];
        out.add(LyricLine(
          startMs: wantSynced && tSec is num ? tSec.toDouble() * 1000 : -1,
          endMs: endSec is num ? endSec.toDouble() * 1000 : null,
          text: text,
        ));
      }
      if (out.isEmpty) return null;
      return LyricsResult(out, wantSynced && out.every((l) => l.startMs >= 0));
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _lrclibGet(Uri uri) async {
    final res = await _http.get(uri, headers: _lrclibHeaders).timeout(const Duration(seconds: 7));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static const _lrclibHeaders = {
    'Accept': 'application/json',
    'User-Agent': 'SoundXs/1.1 (Android; lyrics lookup)',
  };

  int _lrcScore(Map item, _LyricCand c) {
    final title = (item['trackName'] ?? item['name'] ?? '').toString().toLowerCase();
    final artist = (item['artistName'] ?? '').toString().toLowerCase();
    final wt = c.title.toLowerCase();
    final wa = c.artist.toLowerCase();
    var s = 0;
    if (title.isNotEmpty) {
      if (title == wt) {
        s += 4;
      } else if (title.contains(wt) || wt.contains(title)) {
        s += 2;
      }
    }
    if (wa.isNotEmpty && artist == wa) s += 3;
    final synced = item['syncedLyrics'];
    if (synced is String && synced.isNotEmpty) s += 1;
    return s;
  }

  LyricsResult? _parseLrcRecord(Map item) {
    final synced = item['syncedLyrics'];
    final plain = item['plainLyrics'];
    final isSynced = synced is String && synced.trim().isNotEmpty;
    final raw = isSynced ? synced : (plain is String ? plain : '');
    if (raw.trim().isEmpty) return null;

    final lines = <LyricLine>[];
    for (final rawLine in raw.split(RegExp(r'\r?\n'))) {
      final m = _lrcLine.firstMatch(rawLine.trim());
      if (m != null) {
        final fraction = (m.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        final ms = (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000 + int.parse(fraction);
        final text = (m.group(4) ?? '').trim();
        if (text.isNotEmpty) lines.add(LyricLine(startMs: ms.toDouble(), text: text));
      } else if (!isSynced) {
        final text = rawLine.trim();
        if (text.isNotEmpty) lines.add(LyricLine(startMs: -1, text: text));
      }
    }
    if (lines.isEmpty) return null;
    if (isSynced) {
      lines.sort((a, b) => a.startMs.compareTo(b.startMs));
      return LyricsResult(lines, lines.every((l) => l.startMs >= 0));
    }
    return LyricsResult(lines, false);
  }

  Future<LyricsResult?> _lyricsFromLrclib(_LyricCand c, int? duration) async {
    try {
      // 1) Pencocokan tepat (judul + artis + durasi) paling akurat.
      if (c.artist.isNotEmpty && duration != null) {
        final exact = await _lrclibGet(Uri.https('lrclib.net', '/api/get', {
          'track_name': c.title,
          'artist_name': c.artist,
          'duration': '$duration',
        }));
        if (exact != null) {
          final r = _parseLrcRecord(exact);
          if (r != null) return r;
        }
      }
      // 2) Pencarian longgar, pilih kecocokan terdekat.
      final res = await _http
          .get(
            Uri.https('lrclib.net', '/api/search', {
              'track_name': c.title,
              if (c.artist.isNotEmpty) 'artist_name': c.artist,
            }),
            headers: _lrclibHeaders,
          )
          .timeout(const Duration(seconds: 7));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! List) return null;
      final items = decoded.whereType<Map>().toList()
        ..sort((a, b) => _lrcScore(b, c).compareTo(_lrcScore(a, c)));
      for (final item in items.take(5)) {
        final r = _parseLrcRecord(item);
        if (r != null) return r;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Semua kandidat dicoba paralel (backend + LRCLIB). Lirik tersinkron didahulukan.
  Future<LyricsResult> getLyrics(Track t) async {
    final duration = t.durationMs > 0 ? (t.durationMs / 1000).round() : null;
    final cands = _lyricCandidates(t);
    final tasks = <Future<LyricsResult?>>[
      for (final c in cands) _lyricsFromBackend(c, duration),
      for (final c in cands) _lyricsFromLrclib(c, duration),
    ];
    final results = await Future.wait(tasks);

    LyricsResult? best;
    for (final r in results) {
      if (r == null || r.isEmpty) continue;
      if (r.synced) return r;
      best ??= r;
    }
    return best ?? const LyricsResult([], false);
  }
}
