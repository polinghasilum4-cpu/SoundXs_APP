import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/perf.dart';
import '../theme/app_theme.dart';

/// Kaca blur. Di mode hemat (Perf.lite) otomatis jadi warna solid tanpa BackdropFilter.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 24,
    this.blur = 18,
    this.padding,
    this.width,
    this.height,
    this.border = true,
  });

  final Widget child;
  final double radius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return ValueListenableBuilder<bool>(
      valueListenable: Perf.instance.lite,
      child: child,
      builder: (context, lite, child) {
        final box = Container(
          width: width,
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: lite ? C.glassSolid : op(Colors.white, 0.09),
            borderRadius: br,
            border: border ? Border.all(color: op(Colors.white, 0.12)) : null,
          ),
          child: child,
        );
        if (lite) return RepaintBoundary(child: box);
        return RepaintBoundary(
          child: ClipRRect(
            borderRadius: br,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: box,
            ),
          ),
        );
      },
    );
  }
}
