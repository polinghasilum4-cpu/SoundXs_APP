import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class _Cached {
  final List<Track> items;
  final DateTime at = DateTime.now();
  _Cached(this.items);
}

/// Singleton: `ApiService()` selalu mengembalikan instance yang sama,
/// jadi cache + client HTTP dipakai bersama semua layar.
class ApiService {
  ApiService._();
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;

  static const _api = '/api';
  static const _timeout = Duration(seconds: 28);
  static const _ttl = Duration(minutes: 5);

  final http.Client _http = http.Client();
  final Map<String, _Cached> _cache = {};
  final Map<String, Future<List<Track>>> _inflight = {};
  String? _clientId;

  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; SM-A135F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  Future<dynamic> _getJson(Uri uri, {void Function(int status)? onStatus}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _http
            .get(uri, headers: {'Accept': 'application/json', 'User-Agent': _ua})
            .timeout(_timeout);
        onStatus?.call(res.statusCode);
        dynamic data;
        try {
          data = jsonDecode(utf8.decode(res.bodyBytes));
        } catch (_) {
          data = null;
        }
        if (res.statusCode != 200) {
          final msg = data is Map ? data['error'] : null;
          throw ApiException(msg?.toString() ?? 'Server error (${res.statusCode})');
        }
        return data;
      } on TimeoutException {
        if (attempt == 1) throw ApiException('Koneksi lambat, coba lagi.');
      } on SocketException {
        if (attempt == 1) throw ApiException('Tidak ada koneksi internet.');
      } on http.ClientException {
        if (attempt == 1) throw ApiException('Tidak ada koneksi internet.');
      }
    }
    throw ApiException('Koneksi gagal.');
  }

  static const _credKey = 'sc_client_id';
  static const _credAtKey = 'sc_client_id_at';
  static const _credTtlMs = 12 * 60 * 60 * 1000;

  /// client_id disimpan di perangkat (12 jam). Cold start tidak perlu scrape ulang -> lebih cepat.
  Future<String> getCredentials({bool force = false}) async {
    if (_clientId != null && !force) return _clientId!;
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final saved = prefs.getString(_credKey);
      final at = prefs.getInt(_credAtKey) ?? 0;
      if (saved != null && saved.length >= 20 && DateTime.now().millisecondsSinceEpoch - at < _credTtlMs) {
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
      _cache[key] = _Cached(items);
      if (_cache.length > 40) _cache.remove(_cache.keys.first);
      return items;
    }).whenComplete(() => _inflight.remove(key));
    _inflight[key] = f;
    return f;
  }

  Future<List<Track>> _fetchSearch(Map<String, String> params, ItemKind kind) async {
    Uri build(String clientId) => Uri.parse('${ApiConfig.baseUrl}$_api/search')
        .replace(queryParameters: {...params, 'client_id': clientId});

    var status = 200;
    dynamic data;
    try {
      data = await _getJson(build(await getCredentials()), onStatus: (s) => status = s);
    } on ApiException {
      if (status != 401) rethrow;
      data = await _getJson(build(await getCredentials(force: true))); // client_id kedaluwarsa
    }

    if (data is Map && data['success'] == false) {
      throw ApiException(data['error']?.toString() ?? 'Request gagal');
    }
    final list = data is List
        ? data
        : (data is Map ? (data['collection'] ?? data['results'] ?? data['data']) : null);
    if (list is! List) throw ApiException('Format data tidak dikenali');

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
      _requestSearch({'playlist_id': id, 'type': 'tracks'}, ItemKind.track);

  /// URL stream lewat proxy server (sama seperti versi web):
  /// /api/stream?url=<stream_url SoundCloud>&client_id=...&track_authorization=...
  /// Server membalas 302 ke CDN SoundCloud, player mengikuti redirect itu.
  Future<String> proxiedStream(Track t) async {
    if (t.streamUrl.isEmpty) return '';
    final id = await getCredentials();
    return Uri.parse('${ApiConfig.baseUrl}$_api/stream').replace(queryParameters: {
      'url': t.streamUrl,
      'client_id': id,
      if (t.trackAuthorization.isNotEmpty) 'track_authorization': t.trackAuthorization,
    }).toString();
  }

  /// Ambil data lagu terbaru (stream_url + track_authorization) lewat pencarian,
  /// untuk lagu tersimpan/disukai yang datanya sudah kedaluwarsa.
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

  /// Bersihkan judul SoundCloud yang berantakan (emoji, tahun, tag viral, dll).
  static String cleanTitle(String raw) {
    var s = raw;
    // Buang emoji (non-BMP) & simbol
    s = s.replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), ' ');
    s = s.replaceAll(RegExp(r'[\u2600-\u27BF\uFE0F\u200D]'), ' ');
    s = s.replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
    s = s.replaceAll(
      RegExp(
        r'(?i)\b(official|lyrics?|audio|video|mv|hd|hq|viral|tiktok|spotify|music|lagu|terbaru|hits?|pop indonesia|indonesia)\b',
      ),
      ' ',
    );
    s = s.replaceAll(RegExp(r'\b20[0-3][0-9]\b'), ' ');
    final dashParts = s.split(RegExp(r'\s[-\u2013\u2014]\s'));
    if (dashParts.length > 1 && dashParts.first.trim().length >= 2) s = dashParts.first;
    s = s.replaceAll(RegExp(r'[|_~•·]+'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String cleanArtist(String raw) {
    var s = raw.replaceAll(RegExp(r'[\u{10000}-\u{10FFFF}]', unicode: true), ' ');
    s = s.replaceAll(RegExp(r'[\u2600-\u27BF\uFE0F]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static const _lyrKeyPrefix = 'lyr_';

  String _encodeLyrics(LyricsResult r) => jsonEncode({
        'synced': r.synced,
        'lines': r.lines
            .map((l) => {'s': l.startMs, 'e': l.endMs, 't': l.text})
            .toList(),
      });

  LyricsResult? _decodeLyrics(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map;
      final list = (m['lines'] as List)
          .map((e) => LyricLine(
                startMs: (e['s'] as num).toDouble(),
                endMs: e['e'] is num ? (e['e'] as num).toDouble() : null,
                text: e['t'].toString(),
              ))
          .toList();
      if (list.isEmpty) return null;
      return LyricsResult(list, m['synced'] == true);
    } catch (_) {
      return null;
    }
  }

  /// Lirik dibaca dari cache disk dulu (bisa dipakai offline).
  Future<LyricsResult?> cachedLyrics(String trackId) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeLyrics(prefs.getString('$_lyrKeyPrefix$trackId'));
  }

  Future<void> _saveLyrics(String trackId, LyricsResult r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_lyrKeyPrefix$trackId', _encodeLyrics(r));
  }

  /// Parser format LRC: [mm:ss.xx] teks. Dipakai untuk fallback langsung ke LRCLIB.
  static LyricsResult _parseLrc(String lrc) {
    final re = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final out = <LyricLine>[];
    for (final raw in lrc.split(RegExp(r'\r?\n'))) {
      final matches = re.allMatches(raw).toList();
      if (matches.isEmpty) continue;
      final text = raw.substring(matches.last.end).trim();
      if (text.isEmpty) continue;
      for (final m in matches) {
        final min = int.parse(m.group(1)!);
        final sec = int.parse(m.group(2)!);
        final frac = m.group(3) ?? '0';
        final ms = (min * 60 + sec) * 1000 +
            (int.parse(frac.padRight(3, '0').substring(0, 3)));
        out.add(LyricLine(startMs: ms.toDouble(), text: text));
      }
    }
    out.sort((a, b) => a.startMs.compareTo(b.startMs));
    final synced = out.isNotEmpty;
    return LyricsResult(out, synced);
  }

  Future<LyricsResult?> _lrclibDirect(String title, String artist, int? durationSec) async {
    final params = <String, String>{
      'track_name': title,
      'artist_name': artist,
      if (durationSec != null) 'duration': durationSec.toString(),
    };
    final uri = Uri.https('lrclib.net', '/api/get', params);
    try {
      final res = await _http
          .get(uri, headers: {'Accept': 'application/json', 'User-Agent': 'SoundXs/1.1'})
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) return null;
      final synced = data['syncedLyrics'];
      if (synced is String && synced.trim().isNotEmpty) {
        final r = _parseLrc(synced);
        if (r.lines.isNotEmpty) return r;
      }
      final plain = data['plainLyrics'];
      if (plain is String && plain.trim().isNotEmpty) {
        final lines = plain
            .split(RegExp(r'\r?\n'))
            .map((x) => x.trim())
            .where((x) => x.isNotEmpty)
            .map((x) => LyricLine(startMs: -1, text: x))
            .toList();
        if (lines.isNotEmpty) return LyricsResult(lines, false);
      }
    } catch (_) {}
    return null;
  }

  /// Lirik: cache disk -> server /api/lyrics -> LRCLIB langsung. Hasil sukses disimpan ke disk.
  Future<LyricsResult> getLyrics(Track t) async {
    final cached = await cachedLyrics(t.id);
    if (cached != null && cached.synced) return cached;
    final online = await _fetchLyricsOnline(t);
    if (online.isNotEmpty) {
      await _saveLyrics(t.id, online);
      return online;
    }
    final title = cleanTitle(t.title);
    final artist = cleanArtist(t.artist);
    final direct = await _lrclibDirect(
      title.isNotEmpty ? title : t.title,
      artist,
      t.durationMs > 0 ? (t.durationMs / 1000).round() : null,
    );
    if (direct != null && !direct.isEmpty) {
      await _saveLyrics(t.id, direct);
      return direct;
    }
    return cached ?? const LyricsResult([], false);
  }

  /// Lirik dari /api/lyrics (LRCLIB via server). Coba beberapa variasi judul/artis.
  Future<LyricsResult> _fetchLyricsOnline(Track t) async {
    final title0 = cleanTitle(t.title);
    final artist0 = cleanArtist(t.artist);
    final duration = t.durationMs > 0 ? (t.durationMs / 1000).round().toString() : null;

    // Variasi query: judul bersih, judul asli pendek, tanpa artis, dll.
    final attempts = <({String title, String artist})>[
      (title: title0.isNotEmpty ? title0 : t.title, artist: artist0),
      if (title0.contains(' '))
        (title: title0.split(' ').take(4).join(' '), artist: artist0),
      (title: title0.isNotEmpty ? title0 : t.title, artist: ''),
      (title: t.title.length > 60 ? t.title.substring(0, 60) : t.title, artist: artist0),
    ];

    LyricsResult? best;
    for (final a in attempts) {
      if (a.title.trim().length < 2) continue;
      try {
        final params = <String, String>{
          'title': a.title.trim(),
          if (a.artist.trim().isNotEmpty) 'artist': a.artist.trim(),
          if (duration != null) 'duration': duration,
        };
        final data = await _getJson(
          Uri.parse('${ApiConfig.baseUrl}$_api/lyrics').replace(queryParameters: params),
        );
        if (data is! Map || data['success'] != true) continue;
        final raw = data['lines'];
        if (raw is! List || raw.isEmpty) continue;
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
        if (out.isEmpty) continue;
        final synced = wantSynced && out.every((l) => l.startMs >= 0);
        final result = LyricsResult(out, synced);
        if (synced) return result; // prioritas synced
        best ??= result;
      } catch (_) {}
    }
    return best ?? const LyricsResult([], false);
  }
}
