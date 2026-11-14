import 'dart:async';
import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/error_retry.dart';
import '../widgets/press_scale.dart';
import '../widgets/shimmer.dart';
import '../widgets/track_tile.dart';
import 'home_screen.dart' show RecentCard;
import 'track_list_screen.dart';

const _suggestions = ['lofi indonesia', 'pop indonesia', 'indie indonesia', 'remix dj', 'chill lofi', 'focus music'];

class SearchScreen extends StatefulWidget {
  final void Function(Track, List<Track>) onPlay;
  const SearchScreen({super.key, required this.onPlay});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _api = ApiService();
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _tab = 'tracks';
  String _q = '';
  List<Track> _results = [];
  bool _loading = false;
  String? _error;
  int _req = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _q = v.trim();
    _debounce?.cancel();
    if (_q.isEmpty) {
      _req++;
      setState(() {
        _results = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {}); // update tombol clear
    _debounce = Timer(const Duration(milliseconds: 550), _search);
  }

  Future<void> _search() async {
    if (_q.isEmpty) return;
    final id = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Track> res;
      switch (_tab) {
        case 'playlists':
          res = await _api.searchPlaylists(_q);
          break;
        case 'users':
          res = await _api.searchArtists(_q);
          break;
        default:
          res = await _api.search(_q);
      }
      if (!mounted || id != _req) return;
      setState(() {
        _results = res;
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

  void _openItem(Track t) {
    if (t.kind == ItemKind.track) {
      widget.onPlay(t, _results.where((e) => e.kind == ItemKind.track).toList());
      return;
    }
    _focus.unfocus();
    final isPl = t.kind == ItemKind.playlist;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrackListScreen(
        title: t.title,
        subtitle: isPl ? '${t.artist}${t.trackCount > 0 ? ' • ${t.trackCount} lagu' : ''}' : 'Artis',
        coverUrl: t.coverUrl,
        loader: isPl ? () => _api.getPlaylistTracks(t.id) : () => _api.search(t.title),
        onPlay: widget.onPlay,
        playlist: isPl ? t : null,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Text('Cari', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onChanged: _onChanged,
              onSubmitted: (_) {
                _debounce?.cancel();
                _search();
              },
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Cari lagu, playlist, artis...',
                hintStyle: const TextStyle(color: C.dim),
                prefixIcon: const Icon(Icons.search_rounded, color: C.dim),
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, color: C.dim),
                        onPressed: () {
                          _ctrl.clear();
                          _onChanged('');
                        },
                      ),
                filled: true,
                fillColor: op(Colors.white, 0.07),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (_q.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  for (final e in const [('tracks', 'Musik'), ('playlists', 'Playlist'), ('users', 'Artis')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PressScale(
                        onTap: () {
                          if (_tab == e.$1) return;
                          setState(() => _tab = e.$1);
                          _search();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _tab == e.$1 ? C.teal : op(Colors.white, 0.07),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(e.$2,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _tab == e.$1 ? Colors.white : Colors.white60)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _q.isEmpty ? _idle() : _resultsView()),
        ],
      ),
    );
  }

  Widget _resultsView() {
    if (_loading) return const SingleChildScrollView(child: Padding(padding: EdgeInsets.only(top: 12), child: ShimmerList()));
    if (_error != null) return Center(child: ErrorRetry(message: _error!, onRetry: _search));
    if (_results.isEmpty) {
      return const Center(child: Text('Tidak ada hasil.', style: TextStyle(color: C.dim)));
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 12, bottom: kBottomSpace),
      itemCount: _results.length,
      itemBuilder: (_, i) => TrackTile(track: _results[i], onTap: () => _openItem(_results[i])),
    );
  }

  /// Tampilan awal ala Auralys: "Terakhir diputar" (kartu) + "Paling sering diputar" (ranking).
  Widget _idle() {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        final recent = store.recent;
        final top = store.topPlayed(5);
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: 18, bottom: kBottomSpace),
          children: [
            if (recent.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('Terakhir diputar',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              SizedBox(
                height: 176,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: recent.length > 12 ? 12 : recent.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) => RecentCard(track: recent[i], onTap: () => widget.onPlay(recent[i], recent)),
                ),
              ),
            ],
            if (top.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 26, 20, 12),
                child: Text('Paling sering diputar',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              for (var i = 0; i < top.length; i++)
                TrackTile(
                  track: top[i].track,
                  rank: i + 1,
                  subtitle: '${top[i].track.artist} • ${top[i].plays}x diputar',
                  onTap: () => widget.onPlay(top[i].track, top.map((e) => e.track).toList()),
                ),
            ],
            if (recent.isEmpty && top.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Coba cari',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                    const SizedBox(height: 6),
                    const Text('Lagu yang kamu putar akan muncul di sini.',
                        style: TextStyle(color: C.dim, fontSize: 12.5)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in _suggestions)
                          PressScale(
                            onTap: () {
                              _ctrl.text = s;
                              _onChanged(s);
                              _debounce?.cancel();
                              _search();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: op(Colors.white, 0.07),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(s, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
