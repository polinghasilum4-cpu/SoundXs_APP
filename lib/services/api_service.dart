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
  static const _timeout = Duration(seconds: 7);
  static const _ttl = Duration(minutes: 5);
  static const _diskTtl = Duration(minutes: 20);
  static const _maxStale = Duration(days: 7);

  static const _credKey = 'sc_client_id';
  static const _credAtKey = 'sc_client_id_at';
  static const _credTtlMs = 12 * 60 * 60 * 1000;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; SM-A135F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  static final _lrcLine = RegExp(r'^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)$');
  static final _emoji = RegExp(r'[\u{10000}-\u{10FFFF}\u2600-\u27BF\uFE0F\u200D]', unicode: true);
  static final _brackets = RegExp(r'\([^)]*\)|\[[^\]]*\]');
  static final _noise = RegExp(
    r'\b(official|lyrics?|audio|video|mv|hd|hq|viral|tiktok|spotify|music|lagu|terbaru|hits?|pop indonesia|indonesia)\b',
    caseSensitive: false,
  );
  static final _year = RegExp(r'\b20[0-3][0-9]\b');
  static final _space = RegExp(r'\s+');
  static final _sep = RegExp(r'[|_~•·]+');

  final http.Client _http = http.Client();
  final Map<String, _Cached> _cache = {};
  final Map<String, Future<List<Track>>> _inflight = {};
  final Set<String> _revalidating = {};
  String? _clientId;
  Future<String>? _credFuture;

  /// Siapkan client_id; permintaan paralel berbagi future yang sama.
  Future<void> warmUp() async {
    try {
      await getCredentials();
    } catch (_) {}
  }

  /// Mulai request Beranda saat startup; halaman nanti bergabung ke request/cache yang sama.
  Future<void> primeHome() async {
    try {
      await search('Indonesian Pop Hits');
    } catch (_) {}
  }

  Future<dynamic> _getJson(
    Uri uri, {
    void Function(int status)? onStatus,
    Duration? timeout,
    int retries = 2,
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

    final f = _loadOrFetchSearch(key, params, kind).whenComplete(() => _inflight.remove(key));
    _inflight[key] = f;
    return f;
  }

  Future<List<Track>> _loadOrFetchSearch(
    String key,
    Map<String, String> params,
    ItemKind kind,
  ) async {
    final prefsKey = 'api_search_${base64Url.encode(utf8.encode(key))}';
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null) {
        final saved = jsonDecode(raw);
        if (saved is Map && saved['at'] is int && saved['items'] is List) {
          final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(saved['at'] as int));
          if (age <= _maxStale) {
            final items = (saved['items'] as List)
                .whereType<Map>()
                .map((e) => Track.fromJson(Map<String, dynamic>.from(e), kind: kind))
                .where((t) => t.id.isNotEmpty)
                .toList();
            if (items.isNotEmpty) {
              _cache[key] = _Cached(items);
              if (age > _diskTtl) {
                unawaited(_revalidateSearch(key, prefsKey, params, kind));
              }
              return items;
            }
          } else {
            await prefs.remove(prefsKey);
          }
        }
      }
    } catch (_) {}

    final items = await _fetchSearch(params, kind);
    if (items.isNotEmpty) {
      _cache[key] = _Cached(items);
      if (_cache.length > 40) _cache.remove(_cache.keys.first);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(prefsKey, jsonEncode({
          'at': DateTime.now().millisecondsSinceEpoch,
          'items': items.take(250).map((e) => e.toJson()).toList(),
        }));
      } catch (_) {}
    }
    return items;
  }

  /// Cache usang tetap ditampilkan; hasil terbaru ditulis diam-diam untuk kunjungan berikutnya.
  Future<void> _revalidateSearch(
    String key,
    String prefsKey,
    Map<String, String> params,
    ItemKind kind,
  ) async {
    if (!_revalidating.add(key)) return;
    try {
      final items = await _fetchSearch(params, kind);
      if (items.isEmpty) return;
      _cache[key] = _Cached(items);
      if (_cache.length > 40) _cache.remove(_cache.keys.first);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, jsonEncode({
        'at': DateTime.now().millisecondsSinceEpoch,
        'items': items.take(250).map((e) => e.toJson()).toList(),
      }));
    } catch (_) {
      // Cache lama tetap digunakan saat jaringan tidak tersedia.
    } finally {
      _revalidating.remove(key);
    }
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
      data = await _getJson(build(await getCredentials()), onStatus: (s) => status = s, retries: 2);
    } on ApiException {
      if (status != 401) rethrow;
      // client_id kedaluwarsa: ambil yang baru sekali, lalu coba lagi.
      data = await _getJson(build(await getCredentials(force: true)), retries: 1);
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

  Future<void> prefetchTrackList(Track item) async {
    try {
      if (item.kind == ItemKind.playlist) {
        await getPlaylistTracks(item.id);
      } else if (item.kind == ItemKind.user) {
        await getArtistTracks(item);
      }
    } catch (_) {
      // Pemuatan halaman tetap akan mencoba lagi saat item dibuka.
    }
  }

  Future<List<Track>> getAlbumTracks(Track track) async {
    final album = track.albumTitle.trim();
    if (album.isEmpty) return [track];
    final results = await search(album);
    final matches = results.where((candidate) =>
        candidate.albumTitle.trim().toLowerCase() == album.toLowerCase()).toList();
    return matches.isEmpty ? results : matches;
  }

  /// Lagu milik artis. Endpoint SoundXs /search tidak menerima user_id; cari nama artis saja.
  Future<List<Track>> getArtistTracks(Track artist) async {
    final name = artist.title.trim().toLowerCase();
    final byName = await search(artist.title);
    return byName.where((e) => e.artist.trim().toLowerCase() == name).toList();
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
    // Lewati cache: stream URL yang tersimpan dapat kedaluwarsa. Cari dengan variasi
    // judul/artis karena judul SoundCloud sering memuat nama artis di dalamnya.
    final parts = t.title.split(' - ').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final queries = <String>{
      '${t.title} ${t.artist}'.trim(),
      '${t.artist} ${t.title}'.trim(),
      cleanTitle(t.title),
      if (parts.length > 1) parts.first,
      if (parts.length > 1) parts.last,
      if (t.permalinkUrl.isNotEmpty) t.permalinkUrl,
    }..removeWhere((q) => q.isEmpty);
    final results = await Future.wait(queries.map((q) async {
      try {
        return await _fetchSearch({'q': q, 'type': 'tracks'}, ItemKind.track);
      } catch (_) {
        return <Track>[];
      }
    }));
    final candidates = results.expand((e) => e).toList();
    for (final candidate in candidates) {
      if (candidate.id == t.id && candidate.streamUrl.isNotEmpty) return candidate;
    }
    final wantedTitles = <String>{
      cleanTitle(t.title).toLowerCase(),
      ...parts.map((part) => cleanTitle(part).toLowerCase()),
    }..removeWhere((title) => title.isEmpty);
    final sameTitle = candidates.where((candidate) =>
        candidate.streamUrl.isNotEmpty &&
        wantedTitles.contains(cleanTitle(candidate.title).toLowerCase()) &&
        (t.durationMs <= 0 || candidate.durationMs <= 0 ||
            (candidate.durationMs - t.durationMs).abs() <= 15000));
    if (sameTitle.isNotEmpty) return sameTitle.first;
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
    // Judul lengkap + uploader sering menjadi kombinasi terbaik: judul SoundCloud
    // dapat berupa "Artis - Lagu", walau uploader-nya berbeda.
    add(cleanTitle(raw), uploader);
    if (raw.contains(' - ')) {
      final parts = raw.split(' - ');
      final left = cleanTitle(parts.first);
      final right = cleanTitle(parts.sublist(1).join(' - '));
      add(right, left);
      add(left, right);
    }
    add(cleanTitle(raw), '');
    return out.take(4).toList();
  }

  double? _lyricTimeMs(dynamic value) {
    if (value is num) return value.toDouble() * 1000;
    if (value is! String) return null;
    final number = double.tryParse(value.trim());
    if (number != null) return number * 1000;
    final match = _lrcLine.firstMatch('[${value.trim()}]');
    if (match == null) return null;
    final minutes = int.tryParse(match.group(1)!) ?? 0;
    final seconds = int.tryParse(match.group(2)!) ?? 0;
    final fraction = match.group(3) ?? '';
    final millis = fraction.isEmpty ? 0 : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return (minutes * 60 + seconds) * 1000 + millis;
  }

  LyricLine _parseLyricString(String raw) {
    final match = _lrcLine.firstMatch(raw.trim());
    if (match == null) return LyricLine(startMs: -1, text: raw.trim());
    final minutes = int.tryParse(match.group(1)!) ?? 0;
    final seconds = int.tryParse(match.group(2)!) ?? 0;
    final fraction = match.group(3) ?? '';
    final millis = fraction.isEmpty ? 0 : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return LyricLine(
      startMs: (minutes * 60 + seconds) * 1000 + millis,
      text: (match.group(4) ?? '').trim(),
    );
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
      final raw = data['lines'] ?? data['lyrics'];
      final entries = raw is List
          ? raw
          : raw is String
              ? raw.split(RegExp(r'\r?\n'))
              : const <dynamic>[];
      if (entries.isEmpty) return null;
      final out = <LyricLine>[];
      for (final e in entries) {
        if (e is String) {
          final line = _parseLyricString(e);
          if (line.text.isNotEmpty) out.add(line);
          continue;
        }
        if (e is! Map) continue;
        final text = (e['text'] ?? e['line'] ?? e['lyrics'] ?? '').toString().trim();
        if (text.isEmpty) continue;
        final startValue = e['t'] ?? e['start'] ?? e['time'] ?? e['timestamp'] ?? e['startMs'];
        final endValue = e['end'] ?? e['endMs'];
        final startMs = e['startMs'] is num
            ? (e['startMs'] as num).toDouble()
            : _lyricTimeMs(startValue);
        final endMs = e['endMs'] is num
            ? (e['endMs'] as num).toDouble()
            : _lyricTimeMs(endValue);
        out.add(LyricLine(
          startMs: startMs ?? -1,
          endMs: endMs,
          text: text,
        ));
      }
      if (out.isEmpty) return null;
      return LyricsResult(out, out.every((l) => l.startMs >= 0));
    } catch (_) {
      return null;
    }
  }

  /// Semua kandidat lirik diambil dari API SoundXs (soundxs.web.id) saja.
  /// Kandidat paralel mengurangi waktu tunggu tanpa mengirim judul ke layanan lain.
  Future<LyricsResult> getLyrics(Track t) async {
    final duration = t.durationMs > 0 ? (t.durationMs / 1000).round() : null;
    final cands = _lyricCandidates(t);
    final results = await Future.wait(cands.map((c) => _lyricsFromBackend(c, duration)));

    LyricsResult? best;
    for (final result in results) {
      if (result == null || result.isEmpty) continue;
      if (result.synced) return result;
      best ??= result;
    }
    return best ?? const LyricsResult([], false);
  }

}
