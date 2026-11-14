import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Bar equalizer kecil. Animasi hanya jalan saat [playing] = true.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.playing,
    this.color = C.mint,
    this.height = 16,
    this.bars = 4,
    this.barWidth = 3,
  });

  final bool playing;
  final Color color;
  final double height;
  final int bars;
  final double barWidth;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    if (widget.playing) _c.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.playing && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return SizedBox(
            height: widget.height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(widget.bars, (i) {
                final f = widget.playing
                    ? 0.35 + 0.65 * (0.5 + 0.5 * math.sin(2 * math.pi * (_c.value + i * 0.23)))
                    : 0.3;
                return Container(
                  margin: EdgeInsets.symmetric(horizontal: widget.barWidth / 3),
                  width: widget.barWidth,
                  height: widget.height * f,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.barWidth),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
