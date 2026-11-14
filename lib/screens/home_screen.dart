import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/error_retry.dart';
import '../widgets/press_scale.dart';
import '../widgets/shimmer.dart';
import 'profile_screen.dart';
import 'wrapped_screen.dart';

const MOODS = ["Semua", "Santai", "Perjalanan", "Tidur", "Sedih", "Semangat", "Pop Indo", "Indie Indo", "Remix / DJ"];
const MOOD_QUERY = {
  "Semua": "Indonesian Pop Hits",
  "Santai": "lofi indonesia",
  "Perjalanan": "road trip indonesia",
  "Tidur": "sleep music",
  "Sedih": "lagu galau indonesia",
  "Semangat": "semangat workout indonesia",
  "Pop Indo": "pop indonesia",
  "Indie Indo": "indie indonesia",
  "Remix / DJ": "remix dj",
};

const _kRed = Color(0xFFE8554E);

class HomeScreen extends StatefulWidget {
  final void Function(Track track, List<Track> queue) onPlay;
  const HomeScreen({super.key, required this.onPlay});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ApiService();
  String _mood = "Semua";
  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load(_mood);
  }

  Future<void> _load(String mood) async {
    final id = ++_req;
    setState(() {
      _mood = mood;
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.search(MOOD_QUERY[mood]!);
      if (!mounted || id != _req) return;
      setState(() {
        _tracks = res.where((e) => e.kind == ItemKind.track).toList();
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

  void _playRandom() {
    if (_tracks.isEmpty) return;
    final list = List<Track>.from(_tracks)..shuffle(math.Random());
    widget.onPlay(list.first, list);
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(backgroundColor: C.bg, body: page),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final grid = _tracks.take(8).toList();
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: C.mint,
        backgroundColor: C.surface,
        onRefresh: () => _load(_mood),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: _header()),
            SliverToBoxAdapter(child: _chips()),
            if (_loading) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 18), child: ShimmerList())),
            if (!_loading && _tracks.isEmpty)
              SliverToBoxAdapter(
                child: ErrorRetry(
                  message: _error ?? 'Tidak ada lagu ditemukan.',
                  onRetry: () => _load(_mood),
                ),
              ),
            if (!_loading && _tracks.isNotEmpty) ...[
              SliverToBoxAdapter(child: _sectionTitle('Panggilan cepat')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.80,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => i < grid.length ? _gridItem(grid[i]) : _diceItem(),
                    childCount: grid.length + 1,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _quickPicksHeader()),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _row(_tracks[i]),
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
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
      child: Row(
        children: [
          const Expanded(
            child: Text('Beranda', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          IconButton(
            tooltip: 'Statistik',
            onPressed: () => _open(const WrappedScreen()),
            icon: const Icon(Icons.bar_chart_rounded, color: Colors.white70),
          ),
          IconButton(
            tooltip: 'Pengaturan',
            onPressed: () => _open(const ProfileScreen()),
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
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
        itemCount: MOODS.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = MOODS[i];
          final active = g == _mood;
          return PressScale(
            onTap: () => _load(g),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: active ? op(C.mint, 0.22) : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? op(C.mint, 0.7) : op(Colors.white, 0.22)),
              ),
              child: Text(g,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? C.mint : Colors.white70,
                  )),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
        child: Text(s, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
      );

  Widget _gridItem(Track t) {
    return PressScale(
      onTap: () => widget.onPlay(t, _tracks),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (_, c) => CoverImage(url: t.coverUrl, size: c.maxWidth, radius: 16),
            ),
          ),
          const SizedBox(height: 6),
          Text(t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _diceItem() {
    Widget dot() => Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(color: _kRed, shape: BoxShape.circle),
        );
    return PressScale(
      onTap: _playRandom,
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: op(Colors.white, 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: op(Colors.white, 0.10)),
                ),
                child: Stack(
                  children: [
                    Align(alignment: const Alignment(-0.45, -0.45), child: dot()),
                    Align(alignment: const Alignment(0.45, -0.45), child: dot()),
                    Align(alignment: Alignment.center, child: dot()),
                    Align(alignment: const Alignment(-0.45, 0.45), child: dot()),
                    Align(alignment: const Alignment(0.45, 0.45), child: dot()),
                  ],
                ),
              ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Acak',
              style: TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _quickPicksHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          const Expanded(
            child: Text('Pilihan cepat',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          PressScale(
            onTap: () {
              if (_tracks.isNotEmpty) widget.onPlay(_tracks.first, _tracks);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: op(_kRed, 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: op(_kRed, 0.7)),
              ),
              child: const Text('Putar semua',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFF8F88))),
            ),
          ),
        ],
      ),
    );
  }

  void _menu(Track t) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: CoverImage(url: t.coverUrl, size: 44, radius: 8),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(store.isLiked(t.id) ? Icons.favorite_rounded : Icons.favorite_border_rounded),
              title: Text(store.isLiked(t.id) ? 'Hapus dari disukai' : 'Tambah ke disukai'),
              onTap: () {
                store.toggleLike(t);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Putar sekarang'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onPlay(t, _tracks);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Track t) {
    return PressScale(
      onTap: () => widget.onPlay(t, _tracks),
      scale: 0.99,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
        child: Row(
          children: [
            CoverImage(url: t.coverUrl, size: 50, radius: 10),
            const SizedBox(width: 14),
            Expanded(
              child: ValueListenableBuilder<Track?>(
                valueListenable: audioHandler.current,
                builder: (_, cur, __) {
                  final playing = cur?.id == t.id;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: playing ? C.mint : Colors.white)),
                      const SizedBox(height: 2),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: C.sub)),
                    ],
                  );
                },
              ),
            ),
            IconButton(
              onPressed: () => _menu(t),
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}
