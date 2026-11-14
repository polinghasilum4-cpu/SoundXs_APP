import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/perf.dart';
import '../theme/app_theme.dart';

/// Placeholder loading. Satu controller untuk semua baris, dan otomatis
/// berhenti saat widget dilepas (versi lama menjalankan animasi selamanya).
class ShimmerList extends StatefulWidget {
  const ShimmerList({super.key, this.count = 8});
  final int count;

  @override
  State<ShimmerList> createState() => _ShimmerListState();
}

class _ShimmerListState extends State<ShimmerList> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (!Perf.instance.lite.value) _c.repeat();
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
          final a = 0.04 + 0.04 * (0.5 + 0.5 * math.sin(2 * math.pi * _c.value));
          return Column(
            children: List.generate(
              widget.count,
              (_) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: op(Colors.white, a),
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
