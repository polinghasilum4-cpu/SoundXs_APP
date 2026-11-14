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

const GENRES = ["Semua", "Lofi", "Chill", "Focus", "Perjalanan", "Pop Indo", "Indie Indo", "Remix / DJ"];
const GENRE_QUERY = {
  "Semua": "Indonesian Pop Hits",
  "Lofi": "lofi indonesia",
  "Chill": "chill lofi",
  "Focus": "focus music",
  "Perjalanan": "road trip indonesia",
  "Pop Indo": "pop indonesia",
  "Indie Indo": "indie indonesia",
  "Remix / DJ": "remix dj",
};

class HomeScreen extends StatefulWidget {
  final void Function(Track track, List<Track> queue) onPlay;
  const HomeScreen({super.key, required this.onPlay});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  String _genre = "Semua";
  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load(_genre);
  }

  Future<void> _load(String genre) async {
    final id = ++_req; // hasil request lama diabaikan kalau user ganti genre cepat-cepat
    setState(() {
      _genre = genre;
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.search(GENRE_QUERY[genre]!);
      if (!mounted || id != _req) return;
      setState(() {
        _tracks = res;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Selamat pagi';
    if (h < 15) return 'Selamat siang';
    if (h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: C.mint,
        backgroundColor: C.surface,
        onRefresh: () => _load(_genre),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _chips()),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            if (_loading) const SliverToBoxAdapter(child: ShimmerList()),
            if (!_loading && _error != null && _tracks.isEmpty)
              SliverToBoxAdapter(child: ErrorRetry(message: _error!, onRetry: () => _load(_genre))),
            if (!_loading && _tracks.isNotEmpty) ...[
              SliverToBoxAdapter(child: _featured(_tracks.first)),
              SliverToBoxAdapter(
                child: AnimatedBuilder(animation: store, builder: (_, __) => _recentRow()),
              ),
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 22, 20, 10),
                  child: Text('Untuk Kamu',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => TrackTile(track: _tracks[i], onTap: () => widget.onPlay(_tracks[i], _tracks)),
                  childCount: _tracks.length,
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: kBottomSpace)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_greeting(), style: const TextStyle(fontSize: 13, color: C.dim, letterSpacing: 0.4)),
          const SizedBox(height: 2),
          ShaderMask(
            shaderCallback: (b) => const LinearGradient(colors: [C.mint, C.teal, Colors.white]).createShader(b),
            child: const Text('SoundXs',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: GENRES.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = GENRES[i];
          final active = g == _genre;
          return PressScale(
            onTap: () => _load(g),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: active ? C.teal : op(Colors.white, 0.07),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? op(C.mint, 0.5) : op(Colors.white, 0.1)),
              ),
              child: Text(g,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? Colors.white : Colors.white60,
                  )),
            ),
          );
        },
      ),
    );
  }

  Widget _featured(Track t) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: PressScale(
        onTap: () => widget.onPlay(t, _tracks),
        scale: 0.98,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CoverImage(url: t.coverUrl, height: 190, radius: 0),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000)],
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(color: op(C.teal, 0.9), borderRadius: BorderRadius.circular(8)),
                              child: const Text('Pilihan hari ini',
                                  style: TextStyle(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w800)),
                            ),
                            const SizedBox(height: 8),
                            Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                            Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                          ],
                        ),
                      ),
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 30),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recentRow() {
    final items = store.recent;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 24, 20, 12),
          child: Text('Terakhir diputar',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: items.length > 12 ? 12 : items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, i) => RecentCard(track: items[i], onTap: () => widget.onPlay(items[i], items)),
          ),
        ),
      ],
    );
  }
}

/// Kartu album persegi (dipakai juga di layar Cari).
class RecentCard extends StatelessWidget {
  const RecentCard({super.key, required this.track, required this.onTap, this.size = 120});
  final Track track;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: SizedBox(
        width: size,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CoverImage(url: track.coverUrl, size: size, radius: 22),
            const SizedBox(height: 8),
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            Text(track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: C.dim, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
