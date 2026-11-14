enum ItemKind { track, playlist, user }

class Track {
  final String id;
  final String title;
  final String artist;
  final String coverUrl;
  final String streamUrl;
  final int durationMs;
  final String permalinkUrl;
  final String category;
  final ItemKind kind;
  final int trackCount;
  final String streamType;
  final String trackAuthorization;

  /// ID & foto artis (dari objek `user` API) -> dipakai halaman Artis.
  final String artistId;
  final String artistAvatar;

  /// `true` hanya jika penyedia menandai lagu boleh diunduh. `null` = tidak diketahui.
  /// Unduhan offline hanya diizinkan untuk `true` (hormati hak cipta/ketentuan API).
  final bool? downloadable;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.coverUrl,
    this.streamUrl = '',
    this.durationMs = 0,
    this.permalinkUrl = '',
    this.category = 'Semua',
    this.kind = ItemKind.track,
    this.trackCount = 0,
    this.streamType = '',
    this.trackAuthorization = '',
    this.artistId = '',
    this.artistAvatar = '',
    this.downloadable,
  });

  static String _s(dynamic v) => v == null ? '' : v.toString();

  static int _i(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _pick(List<dynamic> candidates) {
    for (final v in candidates) {
      final s = _s(v);
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  factory Track.fromJson(Map<String, dynamic> json, {ItemKind? kind}) {
    final userRaw = json['user'];
    final user = userRaw is Map ? Map<String, dynamic>.from(userRaw) : <String, dynamic>{};

    var artwork = _pick([
      json['artwork_url'],
      json['cover'],
      json['thumbnail'],
      json['image'],
      json['avatar_url'],
      user['avatar_url'],
    ]);
    artwork = artwork.replaceAll('-large.', '-t500x500.');

    ItemKind k = kind ?? ItemKind.track;
    if (kind == null) {
      final name = _s(json['kind']);
      for (final v in ItemKind.values) {
        if (v.name == name) k = v;
      }
    }

    final title = _pick([json['title'], json['name'], json['username']]);
    var artist = _pick([user['username'], json['artist'], json['author'], json['channel']]);
    if (artist.isEmpty) artist = k == ItemKind.user ? 'Artis' : 'Unknown';

    final rawDl = json['downloadable'];
    bool? dl = rawDl is bool ? rawDl : null;
    final policy = _s(json['policy']).toUpperCase();
    if (policy == 'BLOCK') dl = false;

    final id = _pick([json['id'], json['videoId']]);
    return Track(
      id: id,
      title: title.isEmpty ? 'Tanpa judul' : title,
      artist: artist,
      coverUrl: artwork,
      streamUrl: _pick([json['stream_url'], json['audio'], json['audioUrl'], json['url']]),
      durationMs: _i(json['duration']),
      permalinkUrl: _s(json['permalink_url']),
      category: _pick([json['category']]).isEmpty ? 'Semua' : _s(json['category']),
      kind: k,
      trackCount: _i(json['track_count']),
      streamType: _s(json['stream_type']),
      trackAuthorization: _s(json['track_authorization']),
      artistId: k == ItemKind.user ? id : _pick([user['id'], json['artist_id']]),
      artistAvatar: _pick([user['avatar_url'], json['artist_avatar']]),
      downloadable: dl,
    );
  }

  /// stream_url sengaja tidak disimpan (cepat kedaluwarsa) -> di-resolve ulang saat diputar.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artwork_url': coverUrl,
        'duration': durationMs,
        'permalink_url': permalinkUrl,
        'kind': kind.name,
        'track_count': trackCount,
        'stream_url': streamUrl,
        'stream_type': streamType,
        'track_authorization': trackAuthorization,
        'artist_id': artistId,
        'artist_avatar': artistAvatar,
        if (downloadable != null) 'downloadable': downloadable,
      };

  Track copyWith({String? streamUrl}) => Track(
        id: id,
        title: title,
        artist: artist,
        coverUrl: coverUrl,
        streamUrl: streamUrl ?? this.streamUrl,
        durationMs: durationMs,
        permalinkUrl: permalinkUrl,
        category: category,
        kind: kind,
        trackCount: trackCount,
        streamType: streamType,
        trackAuthorization: trackAuthorization,
        artistId: artistId,
        artistAvatar: artistAvatar,
        downloadable: downloadable,
      );

  bool get hasStream => streamUrl.isNotEmpty;
}
