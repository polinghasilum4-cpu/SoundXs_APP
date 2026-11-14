import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Sampul dengan cache memori terkecil (decode sesuai ukuran tampil -> hemat RAM).
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    this.size,
    this.width,
    this.height,
    this.radius = 14,
    this.circle = false,
  });

  final String url;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final bool circle;

  Widget _placeholder(double? w, double? h) => Container(
        width: w,
        height: h,
        color: const Color(0xFF1E2628),
        child: const Center(child: Icon(Icons.music_note_rounded, color: Colors.white24, size: 22)),
      );

  @override
  Widget build(BuildContext context) {
    final w = size ?? width;
    final h = size ?? height;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheW = w != null ? (w * dpr).round() : 700;

    final Widget img = url.isEmpty
        ? _placeholder(w, h)
        : CachedNetworkImage(
            imageUrl: url,
            width: w,
            height: h,
            fit: BoxFit.cover,
            memCacheWidth: cacheW,
            fadeInDuration: const Duration(milliseconds: 120),
            fadeOutDuration: Duration.zero,
            placeholder: (_, __) => _placeholder(w, h),
            errorWidget: (_, __, ___) => _placeholder(w, h),
          );

    if (circle) return ClipOval(child: img);
    if (radius <= 0) return img;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: img);
  }
}
