import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/error_retry.dart';
import '../widgets/shimmer.dart';
import '../widgets/track_tile.dart';

/// Halaman daftar lagu generik: isi playlist atau lagu dari seorang artis.
class TrackListScreen extends StatefulWidget {
  const TrackListScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.loader,
    required this.onPlay,
    this.initialTracks = const [],
    this.playlist,
  });

  final String title;
  final String subtitle;
  final String coverUrl;
  final Future<List<Track>> Function() loader;
  final void Function(Track, List<Track>) onPlay;
  final List<Track> initialTracks;
  final Track? playlist; // kalau diisi, tombol simpan playlist muncul

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  List<Track> _tracks = [];
  bool _loading = true;
  String? _error;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _tracks = List<Track>.from(widget.initialTracks);
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.loader().timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw Exception('Daftar masih memuat. Ketuk coba lagi.'),
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _tracks = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Spacer(),
                    if (widget.playlist != null)
                      AnimatedBuilder(
                        animation: store,
                        builder: (_, __) {
                          final saved = store.isSaved(widget.playlist!.id);
                          return IconButton(
                            icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                color: saved ? C.mint : Colors.white70),
                            onPressed: () => store.toggleSavePlaylist(widget.playlist!),
                          );
                        },
                      ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(children: [
                    CoverImage(url: widget.coverUrl, size: 104, radius: 24),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(widget.subtitle, style: const TextStyle(color: C.dim, fontSize: 12.5)),
                        const SizedBox(height: 10),
                        if (_tracks.isNotEmpty)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(backgroundColor: C.teal),
                            onPressed: () => widget.onPlay(_tracks.first, _tracks),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Putar'),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (_loading && _tracks.isEmpty) const SliverToBoxAdapter(child: ShimmerList(count: 6)),
              if (_loading && _tracks.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text('Memuat lagu lainnya…', style: TextStyle(color: C.dim, fontSize: 12)),
                  ),
                ),
              if (_error != null && _tracks.isEmpty)
                SliverToBoxAdapter(child: ErrorRetry(message: _error!, onRetry: _load)),
              if (_error != null && _tracks.isNotEmpty)
                SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Gagal memuat lagu lain · Coba lagi'),
                    ),
                  ),
                ),
              if (!_loading && _error == null && _tracks.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Tidak ada lagu.', style: TextStyle(color: C.dim))),
                  ),
                ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => TrackTile(track: _tracks[i], onTap: () => widget.onPlay(_tracks[i], _tracks)),
                  childCount: _tracks.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: kBottomSpace)),
            ],
          ),
        ),
      ),
    );
  }
}
