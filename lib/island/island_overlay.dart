import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'island_consts.dart';
import '../widgets/equalizer_bars.dart';

/// Dipanggil dari overlayMain() di main.dart (isolate terpisah dari aplikasi utama).
void runIslandOverlay() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _IslandApp());
}

class _IslandApp extends StatelessWidget {
  const _IslandApp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(backgroundColor: Colors.transparent, body: _IslandView()),
    );
  }
}

class _IslandView extends StatefulWidget {
  const _IslandView();

  @override
  State<_IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<_IslandView> {
  String _title = '';
  String _artist = '';
  String _cover = '';
  bool _playing = false;
  int _pos = 0;
  int _dur = 0;
  String _style = 'classic';
  int _offset = 6;
  bool _lite = false;

  bool _expanded = false;
  Timer? _tick;
  Timer? _autoCollapse;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FlutterOverlayWindow.overlayListener.listen(_onMessage);
    // minta state terbaru dari aplikasi utama
    Future<void>.delayed(const Duration(milliseconds: 200), () => _send('sync'));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _autoCollapse?.cancel();
    super.dispose();
  }

  void _send(String cmd) {
    FlutterOverlayWindow.shareData({'t': 'cmd', 'c': cmd});
  }

  void _onMessage(dynamic m) {
    if (m is! Map || m['t'] != 'state') return;
    final oldOffset = _offset;
    setState(() {
      _title = (m['title'] ?? '').toString();
      _artist = (m['artist'] ?? '').toString();
      _cover = (m['cover'] ?? '').toString();
      _playing = m['playing'] == true;
      _pos = (m['pos'] as num?)?.toInt() ?? 0;
      _dur = (m['dur'] as num?)?.toInt() ?? 0;
      _style = (m['style'] ?? 'classic').toString();
      _offset = (m['offset'] as num?)?.toInt() ?? 6;
      _lite = m['lite'] == true;
    });
    if (_offset != oldOffset) _resizeWindow(_expanded);
    _restartTick();
    if (m['pop'] == true) {
      _expand(auto: true);
    }
  }

  void _restartTick() {
    _tick?.cancel();
    if (_expanded && _playing) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _pos = (_pos + 1000).clamp(0, _dur > 0 ? _dur : 1 << 31).toInt());
      });
    }
  }

  void _resizeWindow(bool expanded) {
    final w = expanded ? kIslandExpandedW : kIslandCollapsedW;
    final h = (expanded ? kIslandExpandedH : kIslandCollapsedH) + _offset;
    FlutterOverlayWindow.resizeOverlay(w, h, false);
  }

  void _expand({bool auto = false}) {
    if (_expanded) {
      _armAutoCollapse(auto ? 4 : 6);
      return;
    }
    _resizeWindow(true); // jendela dibesarkan dulu, lalu isi dianimasikan
    setState(() => _expanded = true);
    _send('sync');
    _restartTick();
    _armAutoCollapse(auto ? 4 : 6);
  }

  void _collapse() {
    if (!_expanded) return;
    _autoCollapse?.cancel();
    setState(() => _expanded = false);
    _restartTick();
    // tunggu animasi mengecil selesai baru kecilkan jendela
    Future<void>.delayed(Duration(milliseconds: _lite ? 20 : 300), () {
      if (mounted && !_expanded) _resizeWindow(false);
    });
  }

  void _armAutoCollapse(int seconds) {
    _autoCollapse?.cancel();
    _autoCollapse = Timer(Duration(seconds: seconds), _collapse);
  }

  void _cmd(String c) {
    _send(c);
    _armAutoCollapse(6);
    _restartTick();
  }

  BorderRadius get _radius {
    final big = _expanded ? 30.0 : 18.0;
    if (_style == 'curved') {
      // "Kelengkungan sudut": menempel ke tepi atas, sudut bawah melengkung besar
      return BorderRadius.only(
        topLeft: const Radius.circular(6),
        topRight: const Radius.circular(6),
        bottomLeft: Radius.circular(big + 4),
        bottomRight: Radius.circular(big + 4),
      );
    }
    return BorderRadius.circular(big);
  }

  @override
  Widget build(BuildContext context) {
    final dur = _lite ? Duration.zero : const Duration(milliseconds: 280);
    return Padding(
      padding: EdgeInsets.only(top: _offset.toDouble()),
      child: Align(
        alignment: Alignment.topCenter,
        child: GestureDetector(
          onTap: _expanded ? null : _expand,
          onVerticalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -150) _collapse();
            if (v > 150) _expand();
          },
          onLongPress: _collapse,
          child: AnimatedContainer(
            duration: dur,
            curve: Curves.easeOutCubic,
            width: (_expanded ? kIslandExpandedW : kIslandCollapsedW).toDouble(),
            height: (_expanded ? kIslandExpandedH : kIslandCollapsedH).toDouble(),
            decoration: BoxDecoration(color: Colors.black, borderRadius: _radius),
            clipBehavior: Clip.antiAlias,
            child: _expanded ? _expandedView() : _collapsedView(),
          ),
        ),
      ),
    );
  }

  Widget _cover40(double s, double r) => ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: _cover.isEmpty
            ? Container(width: s, height: s, color: const Color(0xFF222222),
                child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 16))
            : Image.network(
                _cover,
                width: s,
                height: s,
                fit: BoxFit.cover,
                cacheWidth: (s * 3).round(),
                errorBuilder: (_, __, ___) => Container(width: s, height: s, color: const Color(0xFF222222)),
              ),
      );

  Widget _collapsedView() {
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: kIslandCollapsedW.toDouble(),
      maxWidth: kIslandCollapsedW.toDouble(),
      minHeight: kIslandCollapsedH.toDouble(),
      maxHeight: kIslandCollapsedH.toDouble(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _cover40(24, 12),
            EqualizerBars(playing: _playing, height: 14, bars: 4, barWidth: 2.5),
          ],
        ),
      ),
    );
  }

  String _fmt(int ms) {
    final s = (ms / 1000).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _expandedView() {
    final progress = _dur <= 0 ? 0.0 : (_pos / _dur).clamp(0.0, 1.0).toDouble();
    return OverflowBox(
      alignment: Alignment.topCenter,
      minWidth: kIslandExpandedW.toDouble(),
      maxWidth: kIslandExpandedW.toDouble(),
      minHeight: kIslandExpandedH.toDouble(),
      maxHeight: kIslandExpandedH.toDouble(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          children: [
            Row(
              children: [
                _cover40(52, 14),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(_artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                EqualizerBars(playing: _playing, height: 18, bars: 4, barWidth: 3),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(_fmt(_pos), style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 3.5,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF79C9B8)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(_fmt(_dur), style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _btn(Icons.skip_previous_rounded, 30, () => _cmd('prev')),
                const SizedBox(width: 22),
                _btn(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, 38, () => _cmd('toggle')),
                const SizedBox(width: 22),
                _btn(Icons.skip_next_rounded, 30, () => _cmd('next')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // area sentuh 46dp (sebelumnya ikon 30dp tanpa area -> susah dipencet)
  Widget _btn(IconData icon, double size, VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(child: Icon(icon, color: Colors.white, size: size)),
        ),
      );
}
