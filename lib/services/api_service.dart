import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/track.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
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
  static const _timeout = Duration(seconds: 12);
  static const _ttl = Duration(minutes: 5);

  final http.Client _http = http.Client();
  final Map<String, _Cached> _cache = {};
  final Map<String, Future<List<Track>>> _inflight = {};
  String? _clientId;

  Future<dynamic> _getJson(Uri uri, {void Function(int status)? onStatus}) async {
    try {
      final res = await _http.get(uri, headers: {'Accept': 'application/json'}).timeout(_timeout);
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
      throw ApiException('Koneksi lambat, coba lagi.');
    } on SocketException {
      throw ApiException('Tidak ada koneksi internet.');
    } on http.ClientException {
      throw ApiException('Tidak ada koneksi internet.');
    }
  }

  Future<String> getCredentials({bool force = false}) async {
    if (_clientId != null && !force) return _clientId!;
    final data = await _getJson(Uri.parse('${ApiConfig.baseUrl}$_api/get-credentials'));
    final id = data is Map ? (data['client_id'] ?? data['clientId']) : null;
    if (id is! String || id.length < 20) {
      throw ApiException('Kredensial SoundCloud tidak tersedia');
    }
    _clientId = id;
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

  Future<String> getStreamUrl(String trackId) async {
    final data = await _getJson(
        Uri.parse('${ApiConfig.baseUrl}$_api/stream').replace(queryParameters: {'id': trackId}));
    if (data is! Map) return '';
    return (data['url'] ?? data['audioUrl'] ?? data['streamUrl'] ?? '').toString();
  }

  Future<String> getLyrics(String trackId) async {
    final data = await _getJson(
        Uri.parse('${ApiConfig.baseUrl}$_api/lyrics').replace(queryParameters: {'id': trackId}));
    if (data is! Map) return '';
    return (data['lyrics'] ?? data['text'] ?? '').toString();
  }
}
