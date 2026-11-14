import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/error_retry.dart';
import '../widgets/press_scale.dart';
import '../widgets/shimmer.dart';
import '../widgets/track_tile.dart';
import 'track_list_screen.dart';

/// Profil artis. Semua data berasal dari API SoundXs (pencarian), tidak ada data palsu:
///  - profil/foto: hasil `type=users` yang cocok dengan id/nama artis
///  - lagu: hasil `type=tracks` yang benar-benar milik artis itu
///  - rilisan: hasil `type=playlists` yang dibuat artis itu
class ArtistScreen extends StatefulWidget {
  const ArtistScreen({
    super.key,
    required this.name,
    required this.onPlay,
    this.artistId = '',
    this.avatar = '',
  });

  final String name;
  final String artistId;
  final String avatar;
  final void Function(Track, List<Track>) onPlay;

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  final _api = ApiService();
  List<Track> _tracks = [];
  List<Track> _releases = [];
  Track? _profile;
  bool _loading = true;
  String? _error;

  String get _key => widget.name.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool _sameArtist(Track t) {
    if (widget.artistId.isNotEmpty && t.artistId.isNotEmpty) return t.artistId == widget.artistId;
    return t.artist.trim().toLowerCase() == _key;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Lagu adalah data utama; profil & rilisan boleh gagal tanpa merusak halaman.
      final tracksF = _api.search(widget.name);
      final usersF = _api.searchArtists(widget.name).then<List<Track>>((v) => v, onError: (Object _) => <Track>[]);
      final plF = _api.searchPlaylists(widget.name).then<List<Track>>((v) => v, onError: (Object _) => <Track>[]);

      final tracks = (await tracksF).where(_sameArtist).toList();
      final users = await usersF;
      final pls = await plF;

      Track? profile;
      for (final u in users) {
        if ((widget.artistId.isNotEmpty && u.id == widget.artistId) || u.title.trim().toLowerCase() == _key) {
          profile = u;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _profile = profile;
        _releases = pls.where((p) => p.artist.trim().toLowerCase() == _key).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Track get _artistEntry => Track(
        id: widget.artistId.isNotEmpty ? widget.artistId : (_profile?.id ?? widget.name),
        title: widget.name,
        artist: widget.name,
        coverUrl: _avatar,
        kind: ItemKind.user,
        artistId: widget.artistId.isNotEmpty ? widget.artistId : (_profile?.id ?? ''),
        artistAvatar: _avatar,
      );

  String get _avatar {
    if (_profile != null && _profile!.coverUrl.isNotEmpty) return _profile!.coverUrl;
    return widget.avatar;
  }

  void _play({bool shuffle = false}) {
    if (_tracks.isEmpty) return;
    if (audioHandler.shuffleOn.value != shuffle) audioHandler.toggleShuffle();
    widget.onPlay(_tracks.first, _tracks);
  }

  @override
  Widget build(BuildContext context) {
    final count = (_profile?.trackCount ?? 0) > 0 ? _profile!.trackCount : _tracks.length;
    return Scaffold(
      backgroundColor: C.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.bg2, C.bg]),
        ),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                  child: Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: Column(children: [
                    CoverImage(url: _avatar, size: 124, circle: true),
                    const SizedBox(height: 14),
                    Text(widget.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 4),
                    if (!_loading && count > 0)
                      Text(
                        (_profile?.trackCount ?? 0) > 0 ? '$count lagu' : '$count lagu ditemukan',
                        style: const TextStyle(color: C.dim, fontSize: 13),
                      ),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: C.teal),
                        onPressed: _tracks.isEmpty ? null : () => _play(),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Putar'),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _tracks.isEmpty ? null : () => _play(shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Acak'),
                      ),
                      const SizedBox(width: 10),
                      AnimatedBuilder(
                        animation: store,
                        builder: (_, __) {
                          final entry = _artistEntry;
                          final on = store.isFollowing(entry.id);
                          return PressScale(
                            onTap: () => store.toggleFollowArtist(entry),
                            child: Container(
                              padding: const EdgeInsets.all(11),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: on ? op(C.mint, 0.25) : op(Colors.white, 0.08),
                              ),
                              child: Icon(on ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                  color: on ? C.mint : Colors.white70, size: 22),
                            ),
                          );
                        },
                      ),
                    ]),
                  ]),
                ),
              ),
              if (_loading) const SliverToBoxAdapter(child: ShimmerList(count: 6)),
              if (_error != null) SliverToBoxAdapter(child: ErrorRetry(message: _error!, onRetry: _load)),
              if (!_loading && _error == null && _tracks.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('Belum ada lagu artis ini yang ditemukan.',
                          textAlign: TextAlign.center, style: TextStyle(color: C.dim)),
                    ),
                  ),
                ),
              if (_tracks.isNotEmpty) ...[
                _header('Lagu'),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TrackTile(track: _tracks[i], onTap: () => widget.onPlay(_tracks[i], _tracks)),
                    childCount: _tracks.length,
                  ),
                ),
              ],
              if (_releases.isNotEmpty) ...[
                _header('Playlist & rilisan'),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final p = _releases[i];
                      return TrackTile(
                        track: p,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => TrackListScreen(
                            title: p.title,
                            subtitle: p.artist,
                            coverUrl: p.coverUrl,
                            loader: () => _api.getPlaylistTracks(p.id),
                            onPlay: widget.onPlay,
                            playlist: p,
                          ),
                        )),
                      );
                    },
                    childCount: _releases.length,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: kBottomSpace)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(String t) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
      );
}
