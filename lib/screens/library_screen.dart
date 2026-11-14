import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/press_scale.dart';
import '../widgets/track_tile.dart';
import 'artist_screen.dart';
import 'downloads_screen.dart';
import 'track_list_screen.dart';

class LibraryScreen extends StatelessWidget {
  final void Function(Track, List<Track>) onPlay;
  const LibraryScreen({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final liked = store.liked;
          final saved = store.savedPlaylists;
          final recent = store.recent;
          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: kBottomSpace),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Text('Library', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              _likedCard(liked),
              _downloadsCard(context),
              if (store.followedArtists.isNotEmpty) ...[
                _section('Artis diikuti'),
                for (final a in store.followedArtists)
                  TrackTile(
                    track: a,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ArtistScreen(
                        name: a.title,
                        artistId: a.artistId,
                        avatar: a.artistAvatar.isNotEmpty ? a.artistAvatar : a.coverUrl,
                        onPlay: onPlay,
                      ),
                    )),
                  ),
              ],
              if (saved.isNotEmpty) ...[
                _section('Playlist tersimpan'),
                for (final p in saved)
                  TrackTile(
                    track: p,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => TrackListScreen(
                        title: p.title,
                        subtitle: p.artist,
                        coverUrl: p.coverUrl,
                        loader: () => ApiService().getPlaylistTracks(p.id),
                        onPlay: onPlay,
                        playlist: p,
                      ),
                    )),
                  ),
              ],
              if (liked.isNotEmpty) ...[
                _section('Lagu disukai'),
                for (final t in liked)
                  TrackTile(
                    track: t,
                    onTap: () => onPlay(t, liked),
                    trailing: IconButton(
                      icon: const Icon(Icons.favorite_rounded, color: C.mint, size: 20),
                      onPressed: () => store.toggleLike(t),
                    ),
                  ),
              ],
              if (recent.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 12, 10),
                  child: Row(children: [
                    const Expanded(
                      child: Text('Riwayat',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                    TextButton(onPressed: store.clearHistory, child: const Text('Hapus')),
                  ]),
                ),
                for (final t in recent.take(15)) TrackTile(track: t, onTap: () => onPlay(t, recent)),
              ],
              if (liked.isEmpty && saved.isEmpty && recent.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(28),
                  child: Text('Belum ada apa-apa. Tap ❤ di player buat nyimpen lagu, atau simpan playlist dari hasil pencarian.',
                      style: TextStyle(color: C.dim, height: 1.5)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _downloadsCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: PressScale(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => DownloadsScreen(onPlay: onPlay),
        )),
        child: AnimatedBuilder(
          animation: downloads,
          builder: (_, __) {
            final n = downloads.completed.length;
            final act = downloads.active.length;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: op(Colors.white, 0.06), borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: op(C.teal, 0.35), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.download_done_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Downloaded Music',
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    Text(act > 0 ? '$n lagu • $act diproses' : '$n lagu offline',
                        style: const TextStyle(color: C.dim, fontSize: 12.5)),
                  ]),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
      );

  Widget _likedCard(List<Track> liked) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [C.teal, Color(0xFF1B5F57)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: op(Colors.white, 0.2), borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.favorite_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lagu Disukai',
                  style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
              Text('${liked.length} lagu', style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ]),
          ),
          if (liked.isNotEmpty) ...[
            PressScale(
              onTap: () {
                if (!audioHandler.shuffleOn.value) audioHandler.toggleShuffle();
                onPlay(liked.first, liked);
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.shuffle_rounded, color: Colors.white),
              ),
            ),
            PressScale(
              onTap: () => onPlay(liked.first, liked),
              child: Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 28),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
