import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/perf.dart';
import '../theme/app_theme.dart';

/// Kaca cair (liquid glass): blur, isi putih transparan, dan kilap tipis di sudut kiri atas.
/// Di mode hemat (Perf.lite) otomatis jadi warna solid tanpa BackdropFilter.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.radius = 28,
    this.blur = 22,
    this.tint = 0.10,
    this.padding,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;
  final double blur;
  final double tint;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

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
            color: lite ? C.glassSolid : op(Colors.white, tint),
            borderRadius: br,
            border: Border.all(color: op(Colors.white, lite ? 0.10 : 0.20), width: 0.8),
          ),
          foregroundDecoration: lite
              ? null
              : BoxDecoration(
                  borderRadius: br,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.center,
                    colors: [op(Colors.white, 0.10), op(Colors.white, 0.0)],
                  ),
                ),
          child: child,
        );
        if (lite) {
          return RepaintBoundary(child: ClipRRect(borderRadius: br, child: box));
        }
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
