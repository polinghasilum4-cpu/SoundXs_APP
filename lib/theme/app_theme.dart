import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0E0A0C);
  static const bg2 = Color(0xFF2E1A22);
  static const teal = Color(0xFF8E3F4C);
  static const mint = Color(0xFFFFB3B0);
  static const surface = Color(0xFF24191D);
  static const glassSolid = Color(0xFF2D2227);
  static const sub = Color(0x99FFFFFF);
  static const dim = Color(0x61FFFFFF);
}

/// Warna dengan opacity tanpa withOpacity (deprecated di Flutter baru).
Color op(Color c, double o) =>
    c.withAlpha(math.min(255, math.max(0, (o * 255).round())));

ThemeData buildTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.mint,
      secondary: C.teal,
      surface: C.surface,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

const kBottomSpace = 190.0; // ruang kosong di bawah list (nav + mini player)
