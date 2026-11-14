import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animasi pembuka: matahari tenggelam di laut + pohon kelapa melambai,
/// lalu logo SoundXs muncul dan masuk ke aplikasi. Ketuk layar untuk skip.
class SunsetSplash extends StatefulWidget {
  const SunsetSplash({super.key, required this.next});
  final Widget Function() next;

  @override
  State<SunsetSplash> createState() => _SunsetSplashState();
}

class _SunsetSplashState extends State<SunsetSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 5200));
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });
    _c.forward();
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => widget.next(),
      transitionDuration: const Duration(milliseconds: 600),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0720),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final show = Curves.easeOut.transform(((t - 0.55) / 0.25).clamp(0.0, 1.0));
            final sub = Curves.easeOut.transform(((t - 0.68) / 0.22).clamp(0.0, 1.0));
            return Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _SunsetPainter(t)),
                Align(
                  alignment: const Alignment(0, -0.62),
                  child: Opacity(
                    opacity: show,
                    child: Transform.translate(
                      offset: Offset(0, (1 - show) * 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: const Color(0x99B14DFF), blurRadius: 36, spreadRadius: 2),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/logo.png',
                                width: 112,
                                height: 112,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(width: 112, height: 112),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'SoundXs',
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                              shadows: [Shadow(color: Color(0x88000000), blurRadius: 14)],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Opacity(
                            opacity: sub,
                            child: const Text(
                              'FEEL THE MUSIC',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xCCFFFFFF),
                                letterSpacing: 5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

Color _mix(Color a, Color b, double x) => Color.lerp(a, b, x) ?? a;

class _SunsetPainter extends CustomPainter {
  _SunsetPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.60;
    final p = Curves.easeInOut.transform((t / 0.78).clamp(0.0, 1.0));

    // ---------- Langit ----------
    final skyRect = Rect.fromLTWH(0, 0, w, horizon);
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _mix(const Color(0xFF3B1F5E), const Color(0xFF0B0720), p),
          _mix(const Color(0xFFB5446E), const Color(0xFF2A1048), p),
          _mix(const Color(0xFFFF8A3D), const Color(0xFF6B2347), p),
          _mix(const Color(0xFFFFD27A), const Color(0xFFD2603A), p),
        ],
        stops: const [0.0, 0.45, 0.8, 1.0],
      ).createShader(skyRect);
    canvas.drawRect(skyRect, skyPaint);

    // Bintang muncul belakangan
    final starA = ((p - 0.55) / 0.45).clamp(0.0, 1.0);
    if (starA > 0) {
      final rnd = math.Random(7);
      final sp = Paint();
      for (var i = 0; i < 38; i++) {
        final x = rnd.nextDouble() * w;
        final y = rnd.nextDouble() * horizon * 0.62;
        final tw = 0.5 + 0.5 * math.sin(t * 40 + i);
        sp.color = Color.fromRGBO(255, 255, 255, (starA * (0.35 + 0.55 * tw)).clamp(0.0, 1.0));
        canvas.drawCircle(Offset(x, y), 0.8 + rnd.nextDouble() * 0.9, sp);
      }
    }

    // ---------- Matahari ----------
    final r = w * 0.15;
    final sunX = w * 0.5;
    final sunY = horizon - h * 0.10 + (h * 0.20) * p;

    canvas.save();
    canvas.clipRect(skyRect);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(255, 170, 80, 0.55 * (1 - p * 0.6)),
          const Color(0x00FF7A3D),
        ],
      ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: r * 3.4));
    canvas.drawCircle(Offset(sunX, sunY), r * 3.4, glow);
    final disc = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFF0A8), Color(0xFFFF9A3C), Color(0xFFFF5A3C)],
      ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: r));
    canvas.drawCircle(Offset(sunX, sunY), r, disc);
    canvas.restore();

    // Awan tipis
    final cloud = Paint()..color = Color.fromRGBO(255, 190, 150, 0.22 * (1 - p * 0.7));
    for (var i = 0; i < 3; i++) {
      final cx = ((i * 0.37 + t * 0.06) % 1.3) * w - w * 0.15;
      final cy = horizon * (0.30 + i * 0.17);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(cx, cy), width: w * (0.5 - i * 0.08), height: 9 + i * 2.0),
            const Radius.circular(20)),
        cloud,
      );
    }

    // ---------- Laut ----------
    final seaRect = Rect.fromLTWH(0, horizon, w, h - horizon);
    final seaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _mix(const Color(0xFFB5442E), const Color(0xFF3A1530), p),
          _mix(const Color(0xFF4A1F4F), const Color(0xFF140A2E), p),
          const Color(0xFF07041A),
        ],
      ).createShader(seaRect);
    canvas.drawRect(seaRect, seaPaint);

    // Pantulan matahari di air
    final refl = Paint();
    final seaH = h - horizon;
    for (var i = 0; i < 16; i++) {
      final f = i / 16.0;
      final y = horizon + 4 + f * seaH * 0.5;
      final bw = (r * 2.0) * (1 - f * 0.55) + math.sin(t * 22 + i * 1.7) * 7;
      final a = (0.55 * (1 - f) * (1 - p * 0.75)).clamp(0.0, 1.0);
      refl.color = Color.fromRGBO(255, 190, 110, a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(sunX + math.sin(t * 14 + i) * 4, y), width: bw.abs(), height: 3.2),
            const Radius.circular(2)),
        refl,
      );
    }
    // Garis ombak halus
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x22FFFFFF);
    for (var i = 0; i < 7; i++) {
      final y = horizon + seaH * (0.08 + i * 0.09);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= w; x += 12) {
        path.lineTo(x, y + math.sin(x / 38 + t * 9 + i) * 2.2);
      }
      canvas.drawPath(path, wave);
    }

    // ---------- Pulau kecil + kelapa ----------
    final grow = Curves.easeOutCubic.transform((t / 0.28).clamp(0.0, 1.0));
    final sil = Paint()..color = const Color(0xFF080412);

    final isleL = Path()
      ..moveTo(-10, h)
      ..lineTo(-10, h * 0.925)
      ..quadraticBezierTo(w * 0.18, h * 0.89, w * 0.40, h * 0.945)
      ..quadraticBezierTo(w * 0.46, h * 0.97, w * 0.52, h)
      ..close();
    final isleR = Path()
      ..moveTo(w + 10, h)
      ..lineTo(w + 10, h * 0.90)
      ..quadraticBezierTo(w * 0.86, h * 0.875, w * 0.68, h * 0.94)
      ..quadraticBezierTo(w * 0.62, h * 0.97, w * 0.58, h)
      ..close();
    canvas.drawPath(isleL, sil);
    canvas.drawPath(isleR, sil);

    final sway = math.sin(t * math.pi * 2 * 2.3);
    _palm(canvas, Offset(w * 0.12, h * 0.915), h * 0.44 * grow, 0.20, sway, 1.0, sil);
    _palm(canvas, Offset(w * 0.30, h * 0.935), h * 0.24 * grow, -0.10, -sway * 0.8, 2.0, sil);
    _palm(canvas, Offset(w * 0.90, h * 0.895), h * 0.48 * grow, -0.22, -sway, 3.0, sil);
    _palm(canvas, Offset(w * 0.73, h * 0.932), h * 0.22 * grow, 0.12, sway * 0.7, 4.0, sil);
  }

  void _palm(Canvas canvas, Offset base, double ht, double lean, double sway, double seed, Paint sil) {
    if (ht < 2) return;
    final top = Offset(base.dx + lean * ht + sway * ht * 0.025, base.dy - ht);
    final ctrl = Offset(base.dx + lean * ht * 0.10, base.dy - ht * 0.55);
    final wb = ht * 0.032;
    final wt = ht * 0.016;

    final trunk = Path()
      ..moveTo(base.dx - wb, base.dy)
      ..quadraticBezierTo(ctrl.dx - wb * 0.7, ctrl.dy, top.dx - wt, top.dy)
      ..lineTo(top.dx + wt, top.dy)
      ..quadraticBezierTo(ctrl.dx + wb * 0.7, ctrl.dy, base.dx + wb, base.dy)
      ..close();
    canvas.drawPath(trunk, sil);

    // Daun
    final rnd = math.Random((seed * 1000).toInt());
    const angles = [-172.0, -148.0, -124.0, -100.0, -78.0, -54.0, -30.0, -8.0, 14.0, -196.0];
    for (var i = 0; i < angles.length; i++) {
      final a = angles[i] * math.pi / 180 + sway * 0.07 + math.sin(sway * 1.3 + i) * 0.03;
      final len = ht * (0.40 + rnd.nextDouble() * 0.12);
      final dir = Offset(math.cos(a), math.sin(a));
      final lateral = dir.dx.abs();
      final end = Offset(top.dx + dir.dx * len, top.dy + dir.dy * len + len * 0.34 * lateral);
      final mid = Offset(top.dx + dir.dx * len * 0.55, top.dy + dir.dy * len * 0.55 - len * 0.16);
      final perp = Offset(-dir.dy, dir.dx);
      final wd = len * 0.13;
      final leaf = Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(mid.dx + perp.dx * wd, mid.dy + perp.dy * wd, end.dx, end.dy)
        ..quadraticBezierTo(mid.dx - perp.dx * wd, mid.dy - perp.dy * wd, top.dx, top.dy)
        ..close();
      canvas.drawPath(leaf, sil);
    }
    // Kelapa
    for (var i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(top.dx + (i - 1) * ht * 0.03, top.dy + ht * 0.03), ht * 0.02, sil);
    }
  }

  @override
  bool shouldRepaint(covariant _SunsetPainter old) => old.t != t;
}
