import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Warna dominan sampul (untuk latar player ala Auralys). Decode cuma 24x24 px -> ringan.
class CoverColors {
  static final Map<String, Color> _cache = {};

  static Color? peek(String url) => _cache[url];

  static Future<Color> dominant(String url) async {
    if (url.isEmpty) return C.teal;
    final hit = _cache[url];
    if (hit != null) return hit;

    final done = Completer<Color>();
    final provider = ResizeImage(CachedNetworkImageProvider(url), width: 24, height: 24);
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) async {
        stream.removeListener(listener);
        try {
          final bd = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (bd == null) throw StateError('no data');
          double r = 0, g = 0, b = 0, wsum = 0;
          for (var i = 0; i + 3 < bd.lengthInBytes; i += 4) {
            final pr = bd.getUint8(i).toDouble();
            final pg = bd.getUint8(i + 1).toDouble();
            final pb = bd.getUint8(i + 2).toDouble();
            final mx = math.max(pr, math.max(pg, pb));
            final mn = math.min(pr, math.min(pg, pb));
            final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
            final w = 0.05 + sat * (mx / 255.0); // utamakan warna yang hidup
            r += pr * w;
            g += pg * w;
            b += pb * w;
            wsum += w;
          }
          var c = Color.fromARGB(255, (r / wsum).round(), (g / wsum).round(), (b / wsum).round());
          final hsl = HSLColor.fromColor(c);
          c = hsl
              .withLightness(0.3)
              .withSaturation(math.min(hsl.saturation, 0.7))
              .toColor();
          _cache[url] = c;
          if (!done.isCompleted) done.complete(c);
        } catch (_) {
          if (!done.isCompleted) done.complete(C.teal);
        }
      },
      onError: (Object e, StackTrace? s) {
        stream.removeListener(listener);
        if (!done.isCompleted) done.complete(C.teal);
      },
    );
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 6), onTimeout: () => C.teal);
  }
}
