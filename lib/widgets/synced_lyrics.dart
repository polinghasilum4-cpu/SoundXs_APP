import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Lirik sinkron gaya Spotify:
///  - baris aktif besar, putih, fill kiri → kanan sesuai progress baris
///  - baris sekitar lebih besar dari sebelumnya, pudar
///  - scroll mengikuti baris aktif
///  - ketuk baris untuk seek
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
  double _lineProgress = 0; // 0..1 fill kiri→kanan baris aktif
  StreamSubscription<Duration>? _sub;
  Timer? _resume;
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    _active = _indexAt(widget.current.inMilliseconds.toDouble());
    _lineProgress = _progressAt(widget.current.inMilliseconds.toDouble(), _active);
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
      if (end != null && ms > end + 1500) return -1;
    }
    return ans;
  }

  double _progressAt(double ms, int i) {
    if (i < 0 || i >= widget.lines.length) return 0;
    final line = widget.lines[i];
    final start = line.startMs;
    double end;
    if (line.endMs != null) {
      end = line.endMs!;
    } else if (i + 1 < widget.lines.length) {
      end = widget.lines[i + 1].startMs;
    } else {
      end = start + 4000;
    }
    if (end <= start) return 1;
    return ((ms - start) / (end - start)).clamp(0.0, 1.0);
  }

  void _onPos(Duration p) {
    if (!mounted) return;
    final ms = p.inMilliseconds.toDouble();
    final i = _indexAt(ms);
    final prog = _progressAt(ms, i);
    final lineChanged = i != _active;
    // Update progress sering untuk animasi fill; setState ringan
    if (lineChanged || (i >= 0 && (prog - _lineProgress).abs() > 0.02)) {
      setState(() {
        _active = i;
        _lineProgress = prog;
      });
      if (lineChanged && i >= 0 && !_userDragging) _follow(i);
    }
  }

  void _follow(int i, {bool instant = false}) {
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.45,
      duration: instant ? Duration.zero : const Duration(milliseconds: 650),
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
        final pad = c.maxHeight * 0.38;
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.12, 0.88, 1.0],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.symmetric(vertical: pad, horizontal: 8),
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
    final isActive = widget.synced && i == _active;

    if (!widget.synced) {
      return KeyedSubtree(
        key: _keys[i],
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            l.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    final d = _active < 0 ? 99 : (i - _active).abs();
    final double size;
    final Color dimColor;
    final FontWeight weight;
    // Ukuran lebih besar + putih tegas (mirip Spotify)
    if (d == 0) {
      size = 34;
      dimColor = const Color(0x66FFFFFF);
      weight = FontWeight.w900;
    } else if (d == 1) {
      size = 26;
      dimColor = const Color(0xBBFFFFFF);
      weight = FontWeight.w700;
    } else if (d == 2) {
      size = 22;
      dimColor = const Color(0x77FFFFFF);
      weight = FontWeight.w600;
    } else {
      size = 20;
      dimColor = const Color(0x44FFFFFF);
      weight = FontWeight.w600;
    }

    final baseStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: dimColor,
      height: 1.35,
    );
    final fillStyle = TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: Colors.white,
      height: 1.35,
    );

    return KeyedSubtree(
      key: _keys[i],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSeek(Duration(milliseconds: l.startMs.round())),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: isActive
              ? _KaraokeLine(
                  text: l.text,
                  progress: _lineProgress,
                  baseStyle: baseStyle,
                  fillStyle: fillStyle,
                )
              : AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  style: baseStyle,
                  textAlign: TextAlign.center,
                  child: Text(l.text, textAlign: TextAlign.center),
                ),
        ),
      ),
    );
  }
}

/// Fill putih kiri → kanan (mirip Spotify karaoke) lewat gradient mask.
class _KaraokeLine extends StatelessWidget {
  const _KaraokeLine({
    required this.text,
    required this.progress,
    required this.baseStyle,
    required this.fillStyle,
  });

  final String text;
  final double progress;
  final TextStyle baseStyle;
  final TextStyle fillStyle;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    // Fill putih kiri → kanan (karaoke Spotify): bagian terisi putih penuh, sisa abu
    final soft = (p + 0.06).clamp(0.0, 1.0);
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.white,
            Colors.white,
            Color(0x88FFFFFF),
            Color(0x55FFFFFF),
          ],
          stops: [0.0, p.clamp(0.0, 0.999), soft, 1.0],
        ).createShader(bounds);
      },
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: fillStyle.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
