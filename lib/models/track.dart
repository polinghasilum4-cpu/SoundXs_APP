enum ItemKind { track, playlist, user }

class Track {
  final String id;
  final String title;
  final String artist;
  final String artistId;
  final String coverUrl;
  final String streamUrl;
  final int durationMs;
  final String permalinkUrl;
  final String category;
  final String albumTitle;
  final ItemKind kind;
  final int trackCount;
  final String streamType;
  final String trackAuthorization;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.artistId = '',
    required this.coverUrl,
    this.streamUrl = '',
    this.durationMs = 0,
    this.permalinkUrl = '',
    this.category = 'Semua',
    this.albumTitle = '',
    this.kind = ItemKind.track,
    this.trackCount = 0,
    this.streamType = '',
    this.trackAuthorization = '',
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
    final publisherRaw = json['publisher_metadata'];
    final publisher = publisherRaw is Map
        ? Map<String, dynamic>.from(publisherRaw)
        : <String, dynamic>{};
    final albumRaw = json['album'];
    final album = albumRaw is Map ? Map<String, dynamic>.from(albumRaw) : <String, dynamic>{};

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

    return Track(
      id: _pick([json['id'], json['videoId']]),
      title: title.isEmpty ? 'Tanpa judul' : title,
      artist: artist,
      artistId: _pick([user['id'], json['user_id'], json['artist_id']]),
      coverUrl: artwork,
      streamUrl: _pick([json['stream_url'], json['audio'], json['audioUrl'], json['url']]),
      durationMs: _i(json['duration']),
      permalinkUrl: _s(json['permalink_url']),
      category: _pick([json['category']]).isEmpty ? 'Semua' : _s(json['category']),
      albumTitle: _pick([
        json['album_title'],
        json['release_title'],
        publisher['release_title'],
        album['title'],
        albumRaw is String ? albumRaw : null,
      ]),
      kind: k,
      trackCount: _i(json['track_count']),
      streamType: _s(json['stream_type']),
      trackAuthorization: _s(json['track_authorization']),
    );
  }

  /// Stream URL bisa kedaluwarsa, jadi tetap diperbarui lagi sebelum diputar atau diunduh.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'artist_id': artistId,
        'artwork_url': coverUrl,
        'duration': durationMs,
        'permalink_url': permalinkUrl,
        'category': category,
        'album_title': albumTitle,
        'kind': kind.name,
        'track_count': trackCount,
        'stream_url': streamUrl,
        'stream_type': streamType,
        'track_authorization': trackAuthorization,
      };

  Track copyWith({String? streamUrl}) => Track(
        id: id,
        title: title,
        artist: artist,
        artistId: artistId,
        coverUrl: coverUrl,
        streamUrl: streamUrl ?? this.streamUrl,
        durationMs: durationMs,
        permalinkUrl: permalinkUrl,
        category: category,
        albumTitle: albumTitle,
        kind: kind,
        trackCount: trackCount,
        streamType: streamType,
        trackAuthorization: trackAuthorization,
      );

  bool get hasStream => streamUrl.isNotEmpty;
}
