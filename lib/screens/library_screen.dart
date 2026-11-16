import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/press_scale.dart';
import '../widgets/track_tile.dart';
import 'track_list_screen.dart';

const _kLibTabs = ['Semua', 'Playlist', 'Lagu', 'Album', 'Artis', 'Podcast'];
const _kSongFilters = ['Disukai', 'Riwayat', 'Teratas 50', 'Unduhan'];

/// Pustaka: koleksi lokal (disukai, riwayat, paling sering diputar, playlist tersimpan).
/// Tab Album & Podcast belum punya sumber data, jadi tampil kosong dengan jelas.
class LibraryScreen extends StatefulWidget {
  final void Function(Track, List<Track>) onPlay;
  const LibraryScreen({super.key, required this.onPlay});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _tab = 0;
  int _songFilter = 0;

  List<Track> _songsFor(int filter) {
    switch (filter) {
      case 0:
        return store.liked;
      case 1:
        return store.recent;
      case 2:
        return store.topPlayed(50).map((e) => e.track).toList();
      case 3:
        return store.offlineTracks;
      default:
        return store.topPlayed(50).map((e) => e.track).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: store,
        builder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Pustaka',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
            ),
            _tabBar(),
            if (_tab == 2) _subChips(),
            Expanded(child: _content()),
          ],
        ),
      ),
    );
  }

  Widget _tabBar() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _kLibTabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (_, i) {
          final active = i == _tab;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              _tab = i;
              _songFilter = 0;
            }),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _kLibTabs[i],
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? Colors.white : Colors.white54,
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 2,
                  width: active ? 26 : 0,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _subChips() {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        itemCount: _kSongFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final active = i == _songFilter;
          return PressScale(
            onTap: () => setState(() => _songFilter = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? Colors.white : op(Colors.white, 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                _kSongFilters[i],
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.black : Colors.white70,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content() {
    switch (_tab) {
      case 0:
        return _overview();
      case 1:
        return _playlists();
      case 2:
        return _songs();
      case 4:
        return _artists();
      default:
        return _empty(_tab == 3 ? 'Pustaka album akan muncul di sini' : 'Podcast belum tersedia');
    }
  }

  Widget _overview() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, kBottomSpace),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Text('Koleksi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
        _row(Icons.favorite_rounded, 'Disukai', '${store.liked.length} lagu', () => _jump(2, 0)),
        _row(Icons.history_rounded, 'Riwayat', '${store.recent.length} lagu', () => _jump(2, 1)),
        _row(Icons.trending_up_rounded, 'Teratas saya 50', '${_songsFor(2).length} lagu', () => _jump(2, 2)),
        _row(Icons.download_rounded, 'Unduhan offline', '${store.offlineTracks.length} lagu', () => _jump(2, 3)),
        _row(Icons.queue_music_rounded, 'Playlist tersimpan', '${store.savedPlaylists.length} playlist',
            () => _jump(1, 0)),
      ],
    );
  }

  void _jump(int tab, int filter) => setState(() {
        _tab = tab;
        _songFilter = filter;
      });

  Widget _row(IconData icon, String title, String sub, VoidCallback onTap) {
    return PressScale(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(color: op(Colors.white, 0.05), borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, color: C.mint),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              Text(sub, style: const TextStyle(color: C.dim, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ]),
      ),
    );
  }

  Widget _songs() {
    final list = _songsFor(_songFilter);
    if (list.isEmpty) {
      String msg;
      switch (_songFilter) {
        case 0:
          msg = 'Belum ada lagu disukai. Tap ikon hati di player untuk menyimpan.';
          break;
        case 3:
          msg = 'Belum ada unduhan. Buka player lalu tekan Unduh untuk simpan offline.';
          break;
        default:
          msg = 'Belum ada lagu. Putar lagu untuk mengisi daftar ini.';
      }
      return _empty(msg);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: kBottomSpace),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [
            Text('${list.length} lagu', style: const TextStyle(color: C.sub, fontSize: 13)),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                if (!audioHandler.shuffleOn.value) audioHandler.toggleShuffle();
                widget.onPlay(list.first, list);
              },
              icon: const Icon(Icons.shuffle_rounded, size: 18),
              label: const Text('Acak'),
            ),
            FilledButton.icon(
              onPressed: () => widget.onPlay(list.first, list),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Putar'),
            ),
          ]),
        ),
        for (final t in list)
          TrackTile(
            track: t,
            onTap: () => widget.onPlay(t, list),
            trailing: _songFilter == 0
                ? IconButton(
                    tooltip: 'Hapus dari disukai',
                    icon: const Icon(Icons.favorite_rounded, color: C.mint, size: 20),
                    onPressed: () => store.toggleLike(t),
                  )
                : _songFilter == 3
                    ? IconButton(
                        tooltip: 'Hapus unduhan offline',
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70, size: 21),
                        onPressed: () => _deleteOffline(t),
                      )
                    : null,
          ),
      ],
    );
  }

  Future<void> _deleteOffline(Track track) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Hapus unduhan?'),
        content: Text('“${track.title}” akan dihapus dari penyimpanan offline.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await store.removeOffline(track.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(deleted ? 'Unduhan dihapus' : 'File offline tidak dapat dihapus'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _playlists() {
    final saved = store.savedPlaylists;
    if (saved.isEmpty) return _empty('Playlist akan muncul di sini. Simpan dari hasil pencarian.');
    return ListView(
      padding: const EdgeInsets.only(bottom: kBottomSpace),
      children: [
        for (final p in saved)
          TrackTile(
            track: p,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => TrackListScreen(
                title: p.title,
                subtitle: p.artist,
                coverUrl: p.coverUrl,
                loader: () => ApiService().getPlaylistTracks(p.id),
                onPlay: widget.onPlay,
                playlist: p,
              ),
            )),
          ),
      ],
    );
  }

  /// Artis dari lagu disukai & riwayat. Ketuk -> putar lagu artis itu.
  Widget _artists() {
    final byArtist = <String, List<Track>>{};
    for (final t in [...store.liked, ...store.recent]) {
      byArtist.putIfAbsent(t.artist, () => []);
      if (!byArtist[t.artist]!.any((e) => e.id == t.id)) byArtist[t.artist]!.add(t);
    }
    if (byArtist.isEmpty) return _empty('Pustaka artis akan muncul di sini');
    final names = byArtist.keys.toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: kBottomSpace),
      children: [
        for (final n in names)
          ListTile(
            leading: CoverImage(url: byArtist[n]!.first.coverUrl, size: 48, circle: true),
            title: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            subtitle: Text('${byArtist[n]!.length} lagu', style: const TextStyle(color: C.dim)),
            onTap: () => widget.onPlay(byArtist[n]!.first, byArtist[n]!),
          ),
      ],
    );
  }

  Widget _empty(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/logo.png', width: 56, height: 56, errorBuilder: (_, __, ___) => const SizedBox()),
          const SizedBox(height: 14),
          Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: C.dim, height: 1.5)),
        ]),
      ),
    );
  }
}
