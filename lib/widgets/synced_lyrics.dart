import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Lirik yang ngikutin audio (gaya Auralys):
///  - baris aktif di tengah, besar dan terang; baris sekitarnya pudar
///  - scroll mengikuti baris aktif dengan animasi halus
///  - ketuk baris untuk loncat ke waktu itu
///  - kalau user scroll manual, auto-follow berhenti sebentar lalu lanjut lagi
class SyncedLyrics extends StatefulWidget {
  const SyncedLyrics({
    super.key,
    required this.lines,
    required this.synced,
    required this.current,
    required this.position,
    required this.onSeek,
  });

  final List<LyricLine> lines;
  final bool synced;
  final Duration current;
  final Stream<Duration> position;
  final ValueChanged<Duration> onSeek;

  @override
  State<SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<SyncedLyrics> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys = List.generate(widget.lines.length, (_) => GlobalKey());
  int _active = -1;
  StreamSubscription<Duration>? _sub;
  Timer? _resume;
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    _active = _indexAt(widget.current.inMilliseconds.toDouble());
    if (widget.synced) {
      _sub = widget.position.listen(_onPos);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _active >= 0) _follow(_active, instant: true);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _resume?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  /// Cari baris terakhir yang startMs-nya <= posisi (binary search).
  int _indexAt(double ms) {
    if (!widget.synced || widget.lines.isEmpty) return -1;
    var lo = 0;
    var hi = widget.lines.length - 1;
    var ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) ~/ 2;
      if (widget.lines[mid].startMs <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (ans >= 0) {
      final end = widget.lines[ans].endMs;
      // jeda instrumental panjang: tidak ada baris yang disorot
      if (end != null && ms > end + 1500) return -1;
    }
    return ans;
  }

  void _onPos(Duration p) {
    if (!mounted) return;
    final i = _indexAt(p.inMilliseconds.toDouble());
    if (i == _active) return; // setState hanya saat baris berganti
    setState(() => _active = i);
    if (i >= 0 && !_userDragging) _follow(i);
  }

  void _follow(int i, {bool instant = false}) {
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: instant ? Duration.zero : const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userDragging = true;
      _resume?.cancel();
    } else if (n is ScrollEndNotification && _userDragging) {
      _resume?.cancel();
      _resume = Timer(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        _userDragging = false;
        _follow(_active);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lines.isEmpty) {
      return const Center(child: Text('Lirik tidak tersedia', style: TextStyle(color: C.dim)));
    }
    return LayoutBuilder(
      builder: (context, c) {
        final pad = c.maxHeight * 0.42; // ruang atas-bawah supaya baris pertama/terakhir bisa ke tengah
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.16, 0.84, 1.0],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.symmetric(vertical: pad, horizontal: 12),
              child: Column(
                children: [for (var i = 0; i < widget.lines.length; i++) _line(i)],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _line(int i) {
    final l = widget.lines[i];
    final TextStyle style;
    if (!widget.synced) {
      style = const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white70, height: 1.4);
    } else {
      final d = _active < 0 ? 99 : (i - _active).abs();
      if (d == 0) {
        style = const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, height: 1.3);
      } else if (d == 1) {
        style = const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: Color(0x8CFFFFFF), height: 1.35);
      } else {
        style = const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0x40FFFFFF), height: 1.35);
      }
    }
    return KeyedSubtree(
      key: _keys[i],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.synced ? () => widget.onSeek(Duration(milliseconds: l.startMs.round())) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            style: style,
            textAlign: TextAlign.center,
            child: Text(l.text, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }
}
