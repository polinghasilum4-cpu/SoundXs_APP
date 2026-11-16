import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Lirik sinkron gaya Spotify:
///  - rata kiri, teks besar
///  - baris aktif putih + fill kiri→kanan mengikuti progress audio
///  - baris lain pudar
///  - auto-scroll mengikuti baris aktif
///  - ketuk baris untuk seek
class SyncedLyrics extends StatefulWidget {
  const SyncedLyrics({
    super.key,
    required this.lines,
    required this.synced,
    required this.current,
    required this.position,
    required this.onSeek,
    this.followPosition = true,
    this.showIntervals = false,
  });

  final List<LyricLine> lines;
  final bool synced;
  final Duration current;
  final Stream<Duration> position;
  final ValueChanged<Duration> onSeek;
  final bool followPosition;
  final bool showIntervals;

  @override
  State<SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<SyncedLyrics> {
  final _scroll = ScrollController();
  late final List<GlobalKey> _keys =
      List.generate(widget.lines.length, (_) => GlobalKey());
  int _active = -1;
  double _lineProgress = 0;
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
        if (mounted && _active >= 0 && widget.followPosition) _follow(_active, instant: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant SyncedLyrics old) {
    super.didUpdateWidget(old);
    if (old.lines.length != widget.lines.length) {
      _keys
        ..clear()
        ..addAll(List.generate(widget.lines.length, (_) => GlobalKey()));
    }
    if (old.synced != widget.synced) {
      _sub?.cancel();
      _sub = widget.synced ? widget.position.listen(_onPos) : null;
      final ms = widget.current.inMilliseconds.toDouble();
      _active = _indexAt(ms);
      _lineProgress = _progressAt(ms, _active);
      if (widget.synced && widget.followPosition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _follow(_active, instant: true);
        });
      }
    }
    if (!old.followPosition && widget.followPosition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _follow(_active);
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
      if (end != null && ms > end + 2000) return -1;
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
    // Update sering agar animasi fill halus
    if (lineChanged || (i >= 0 && (prog - _lineProgress).abs() > 0.015)) {
      setState(() {
        _active = i;
        _lineProgress = prog;
      });
      if (lineChanged && i >= 0 && !_userDragging && widget.followPosition) _follow(i);
    }
  }

  void _follow(int i, {bool instant = false}) {
    if (!widget.followPosition && !instant) return;
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.35,
      duration: instant ? Duration.zero : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollStartNotification && n.dragDetails != null) {
      _userDragging = true;
      _resume?.cancel();
    } else if (n is ScrollEndNotification && _userDragging) {
      _resume?.cancel();
      _resume = Timer(const Duration(milliseconds: 2200), () {
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
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Lirik tidak tersedia untuk lagu ini.\nCoba lagu dengan judul yang lebih jelas.',
            textAlign: TextAlign.center,
            style: TextStyle(color: C.dim, height: 1.4),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final topPad = c.maxHeight * 0.28;
        final bottomPad = c.maxHeight * 0.42;
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.10, 0.82, 1.0],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, topPad, 28, bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < widget.lines.length; i++) ...[
                    if (widget.showIntervals && widget.synced && _gapBefore(i) >= 5000) _interval(_gapBefore(i)),
                    _line(i),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  double _gapBefore(int i) {
    if (i <= 0 || i >= widget.lines.length) return 0;
    final previous = widget.lines[i - 1];
    final end = previous.endMs ?? previous.startMs + 4000;
    return widget.lines[i].startMs - end;
  }

  Widget _interval(double gapMs) {
    final seconds = (gapMs / 1000).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0x33FFFFFF))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text('Jeda • ${seconds}s', style: const TextStyle(color: C.dim, fontSize: 11)),
          ),
          const Expanded(child: Divider(color: Color(0x33FFFFFF))),
        ],
      ),
    );
  }

  Widget _line(int i) {
    final l = widget.lines[i];
    final isActive = widget.synced && i == _active;

    // Mode non-synced: semua putih besar, rata kiri
    if (!widget.synced) {
      return KeyedSubtree(
        key: _keys[i],
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(
            l.text,
            textAlign: TextAlign.left,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.35,
              letterSpacing: -0.3,
            ),
          ),
        ),
      );
    }

    final d = _active < 0 ? 99 : (i - _active).abs();
    final double size;
    final Color color;
    final FontWeight weight;

    if (d == 0) {
      size = 32;
      color = Colors.white;
      weight = FontWeight.w800;
    } else if (d == 1) {
      size = 24;
      color = const Color(0x99FFFFFF);
      weight = FontWeight.w600;
    } else if (d == 2) {
      size = 22;
      color = const Color(0x55FFFFFF);
      weight = FontWeight.w600;
    } else {
      size = 20;
      color = const Color(0x33FFFFFF);
      weight = FontWeight.w500;
    }

    // Baris yang sudah lewat sedikit lebih pudar
    final past = _active >= 0 && i < _active;
    final baseColor = past ? const Color(0x44FFFFFF) : color;

    return KeyedSubtree(
      key: _keys[i],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSeek(Duration(milliseconds: l.startMs.round())),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              color: baseColor,
              height: 1.3,
              letterSpacing: -0.35,
            ),
            child: isActive
                ? _KaraokeFill(
                    text: l.text,
                    progress: _lineProgress,
                    size: size,
                    weight: weight,
                  )
                : Text(l.text, textAlign: TextAlign.left),
          ),
        ),
      ),
    );
  }
}

/// Fill putih kiri → kanan mengikuti progress baris (karaoke Spotify).
class _KaraokeFill extends StatelessWidget {
  const _KaraokeFill({
    required this.text,
    required this.progress,
    required this.size,
    required this.weight,
  });

  final String text;
  final double progress;
  final double size;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final soft = (p + 0.05).clamp(0.0, 1.0);

    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.white,
            Colors.white,
            Color(0x66FFFFFF),
            Color(0x44FFFFFF),
          ],
          stops: [0.0, p.clamp(0.0, 0.999), soft, 1.0],
        ).createShader(bounds);
      },
      child: Text(
        text,
        textAlign: TextAlign.left,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: Colors.white,
          height: 1.3,
          letterSpacing: -0.35,
        ),
      ),
    );
  }
}
