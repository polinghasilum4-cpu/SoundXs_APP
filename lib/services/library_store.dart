import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';

class TopEntry {
  final Track track;
  final int plays;
  const TopEntry(this.track, this.plays);
}

/// Semua data lokal: lagu disukai, riwayat, hitungan putar, playlist tersimpan, unduhan offline, pengaturan.
class LibraryStore extends ChangeNotifier {
  SharedPreferences? _prefs;
  Timer? _saveTimer;

  List<Track> liked = [];
  List<Track> recent = [];
  List<Track> savedPlaylists = [];
  final Map<String, String> lyricOverrides = {};
  final Map<String, int> _plays = {};
  final Map<String, Track> _meta = {};
  /// trackId -> path file lokal untuk offline
  final Map<String, String> offlinePaths = {};

  // Pengaturan Dynamic Island
  bool islandOn = false;
  String islandStyle = 'classic'; // classic | curved
  bool islandPop = true; // kartu melebar otomatis saat ganti lagu
  int islandOffset = 6; // dp dari tepi atas layar (Android)

  // Performa: 0 = auto, 1 = hemat, 2 = penuh
  int perfMode = 0;

  Future<void> load() async {
    final p = _prefs = await SharedPreferences.getInstance();
    liked = _readList(p.getString('lib_liked'));
    recent = _readList(p.getString('lib_recent'));
    savedPlaylists = _readList(p.getString('lib_saved_pl'));

    try {
      final plays = jsonDecode(p.getString('lib_plays') ?? '{}');
      if (plays is Map) {
        plays.forEach((k, v) => _plays[k.toString()] = v is int ? v : (v as num).toInt());
      }
      final meta = jsonDecode(p.getString('lib_meta') ?? '{}');
      if (meta is Map) {
        meta.forEach((k, v) {
          if (v is Map) _meta[k.toString()] = Track.fromJson(Map<String, dynamic>.from(v));
        });
      }
      final off = jsonDecode(p.getString('lib_offline') ?? '{}');
      if (off is Map) {
        off.forEach((k, v) {
          if (v is String && v.isNotEmpty) offlinePaths[k.toString()] = v;
        });
      }
      // Bersihkan catatan offline yatim dari file yang sudah dihapus / versi lama.
      final stale = offlinePaths.entries
          .where((e) => !File(e.value).existsSync())
          .map((e) => e.key)
          .toList();
      for (final id in stale) {
        offlinePaths.remove(id);
      }
      if (stale.isNotEmpty) {
        await p.setString('lib_offline', jsonEncode(offlinePaths));
      }
      final lyricRaw = jsonDecode(p.getString('lib_lyrics') ?? '{}');
      if (lyricRaw is Map) {
        lyricRaw.forEach((k, v) {
          if (v is String && v.trim().isNotEmpty) lyricOverrides[k.toString()] = v;
        });
      }
    } catch (_) {}

    islandOn = p.getBool('island_on') ?? false;
    islandStyle = p.getString('island_style') ?? 'classic';
    islandPop = p.getBool('island_pop') ?? true;
    islandOffset = (p.getInt('island_offset') ?? 6).clamp(0, 60).toInt();
    perfMode = (p.getInt('perf_mode') ?? 0).clamp(0, 2).toInt();
  }

  List<Track> _readList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final l = jsonDecode(raw);
      if (l is! List) return [];
      return l
          .whereType<Map>()
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => t.id.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ───────────── Disukai ─────────────
  bool isLiked(String id) => liked.any((t) => t.id == id);

  void toggleLike(Track t) {
    if (isLiked(t.id)) {
      liked = liked.where((e) => e.id != t.id).toList();
    } else {
      liked = [t, ...liked];
    }
    _changed();
  }

  // ───────────── Playlist tersimpan ─────────────
  bool isSaved(String id) => savedPlaylists.any((t) => t.id == id);

  void toggleSavePlaylist(Track p) {
    if (isSaved(p.id)) {
      savedPlaylists = savedPlaylists.where((e) => e.id != p.id).toList();
    } else {
      savedPlaylists = [p, ...savedPlaylists];
    }
    _changed();
  }

  // ───────────── Riwayat & statistik ─────────────
  void recordPlay(Track t) {
    if (t.kind != ItemKind.track) return;
    recent = [t, ...recent.where((e) => e.id != t.id)];
    if (recent.length > 30) recent = recent.sublist(0, 30);
    _plays[t.id] = (_plays[t.id] ?? 0) + 1;
    _meta[t.id] = t;
    _prune();
    _changed();
  }

  void _prune() {
    const max = 250;
    if (_meta.length <= max) return;
    final ids = _meta.keys.toList()
      ..sort((a, b) => (_plays[a] ?? 0).compareTo(_plays[b] ?? 0));
    for (final id in ids.take(_meta.length - max)) {
      _meta.remove(id);
      _plays.remove(id);
    }
  }

  List<TopEntry> topPlayed(int n) {
    final entries = _meta.values
        .where((t) => (_plays[t.id] ?? 0) > 0)
        .map((t) => TopEntry(t, _plays[t.id]!))
        .toList()
      ..sort((a, b) => b.plays.compareTo(a.plays));
    return entries.take(n).toList();
  }

  int get totalPlays => _plays.values.fold(0, (a, b) => a + b);

  /// Perkiraan: jumlah putar x durasi lagu.
  int get estimatedMinutes {
    var ms = 0;
    _plays.forEach((id, c) => ms += (_meta[id]?.durationMs ?? 0) * c);
    return (ms / 60000).round();
  }

  List<MapEntry<String, int>> topArtists(int n) {
    final map = <String, int>{};
    _plays.forEach((id, c) {
      final a = _meta[id]?.artist;
      if (a != null) map[a] = (map[a] ?? 0) + c;
    });
    final l = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return l.take(n).toList();
  }

  String? lyricsOverride(String id) => lyricOverrides[id];

  void setLyricsOverride(String id, String? lyrics) {
    final value = lyrics?.trim() ?? '';
    if (value.isEmpty) {
      lyricOverrides.remove(id);
    } else {
      lyricOverrides[id] = value;
    }
    _changed();
  }

  void clearHistory() {
    recent = [];
    _plays.clear();
    _meta.clear();
    _changed();
  }

  // ───────────── Offline / Unduhan ─────────────
  bool isOffline(String id) => offlinePaths.containsKey(id);

  String? offlinePath(String id) => offlinePaths[id];

  void markOffline(Track t, String filePath) {
    offlinePaths[t.id] = filePath;
    _meta[t.id] = t;
    _changed();
  }

  Future<bool> removeOffline(String id) async {
    final path = offlinePaths[id];
    if (path == null || path.isEmpty) return false;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      return false;
    }
    offlinePaths.remove(id);
    _changed();
    return true;
  }

  List<Track> get offlineTracks {
    final list = <Track>[];
    for (final id in offlinePaths.keys) {
      final t = _meta[id];
      if (t != null) list.add(t);
    }
    return list;
  }

  // ───────────── Pengaturan ─────────────
  void setIsland({bool? on, String? style, bool? pop, int? offset}) {
    if (on != null) islandOn = on;
    if (style != null) islandStyle = style;
    if (pop != null) islandPop = pop;
    if (offset != null) islandOffset = offset.clamp(0, 60).toInt();
    _changed();
  }

  void setPerfMode(int m) {
    perfMode = m.clamp(0, 2).toInt();
    _changed();
  }

  // ───────────── Simpan (di-debounce biar tidak spam disk) ─────────────
  void _changed() {
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    String enc(List<Track> l) => jsonEncode(l.map((e) => e.toJson()).toList());
    await p.setString('lib_liked', enc(liked));
    await p.setString('lib_recent', enc(recent));
    await p.setString('lib_saved_pl', enc(savedPlaylists));
    await p.setString('lib_plays', jsonEncode(_plays));
    await p.setString('lib_meta', jsonEncode(_meta.map((k, v) => MapEntry(k, v.toJson()))));
    await p.setString('lib_offline', jsonEncode(offlinePaths));
    await p.setString('lib_lyrics', jsonEncode(lyricOverrides));
    await p.setBool('island_on', islandOn);
    await p.setString('island_style', islandStyle);
    await p.setBool('island_pop', islandPop);
    await p.setInt('island_offset', islandOffset);
    await p.setInt('perf_mode', perfMode);
  }
}
