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
  bool _shuffle = false;
  bool _liked = false;
  double? _drag; // 0..1 saat seek bar digeser

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

  void _send(String cmd, {Object? v}) {
    FlutterOverlayWindow.shareData({'t': 'cmd', 'c': cmd, if (v != null) 'v': v});
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
      _shuffle = m['shuffle'] == true;
      _liked = m['liked'] == true;
    });
    if (_offset != oldOffset) _resizeWindow(_expanded);
    _restartTick();
    if (m['pop'] == true) {
      _expand(auto: true);
    }
  }

  void _restartTick() {
    _tick?.cancel();
    if (_expanded && _playing && _drag == null) {
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
    _send('expanded', v: true); // main mulai kirim posisi asli tiap detik
    _restartTick();
    _armAutoCollapse(auto ? 4 : 6);
  }

  void _collapse() {
    if (!_expanded) return;
    _autoCollapse?.cancel();
    setState(() {
      _expanded = false;
      _drag = null;
    });
    _send('expanded', v: false);
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
    // update optimistis; nilai sebenarnya segera ditimpa state dari AudioHandler
    if (c == 'toggle') setState(() => _playing = !_playing);
    if (c == 'shuffle') setState(() => _shuffle = !_shuffle);
    if (c == 'like') setState(() => _liked = !_liked);
    _restartTick();
  }

  void _seekTo(double frac) {
    if (_dur <= 0) return;
    final f = frac.clamp(0.0, 1.0).toDouble();
    setState(() {
      _pos = (f * _dur).round();
      _drag = null;
    });
    _send('seek', v: _pos);
    _armAutoCollapse(6);
    _restartTick();
  }

  Widget _seekBar(double progress) {
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth <= 0 ? 1.0 : box.maxWidth;
      final shown = (_drag ?? progress).clamp(0.0, 1.0).toDouble();
      double frac(Offset o) => (o.dx / w).clamp(0.0, 1.0).toDouble();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _seekTo(frac(d.localPosition)),
        onHorizontalDragStart: (d) {
          _autoCollapse?.cancel();
          _tick?.cancel();
          setState(() => _drag = frac(d.localPosition));
        },
        onHorizontalDragUpdate: (d) => setState(() => _drag = frac(d.localPosition)),
        onHorizontalDragEnd: (_) => _seekTo(_drag ?? progress),
        onHorizontalDragCancel: () {
          setState(() => _drag = null);
          _restartTick();
        },
        child: SizedBox(
          height: 24,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
              Container(
                height: 4,
                width: w * shown,
                decoration: BoxDecoration(color: const Color(0xFF79C9B8), borderRadius: BorderRadius.circular(2)),
              ),
              Positioned(
                left: (w * shown - 6).clamp(0.0, w - 12).toDouble(),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
        ),
      );
    });
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
    final shownPos = _drag != null && _dur > 0 ? (_drag! * _dur).round() : _pos;
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
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 34,
                  child: Text(_fmt(shownPos), style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                ),
                Expanded(child: _seekBar(progress)),
                SizedBox(
                  width: 34,
                  child: Text(_fmt(_dur),
                      textAlign: TextAlign.right, style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _btn(Icons.shuffle_rounded, 22, () => _cmd('shuffle'),
                    color: _shuffle ? const Color(0xFF79C9B8) : Colors.white54),
                _btn(Icons.skip_previous_rounded, 30, () => _cmd('prev')),
                _btn(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, 38, () => _cmd('toggle')),
                _btn(Icons.skip_next_rounded, 30, () => _cmd('next')),
                _btn(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, 22, () => _cmd('like'),
                    color: _liked ? const Color(0xFFFFB3B0) : Colors.white54),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(IconData icon, double size, VoidCallback onTap, {Color color = Colors.white}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: size),
        ),
      );
}
