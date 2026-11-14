import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/liquid_glass.dart';

/// Pembuka minimalis: kotak liquid glass muncul di tengah layar,
/// lalu logo dan nama animasi MUNCUL DI DALAM kotak itu. Ketuk layar untuk skip.
class GlassSplash extends StatefulWidget {
  const GlassSplash({super.key, required this.next});
  final Widget Function() next;

  @override
  State<GlassSplash> createState() => _GlassSplashState();
}

class _GlassSplashState extends State<GlassSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _go();
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      pageBuilder: (_, __, ___) => widget.next(),
      transitionDuration: const Duration(milliseconds: 500),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
    ));
  }

  double _seg(double t, double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0).toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _go,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            final boxIn = Curves.easeOutBack.transform(_seg(t, 0.00, 0.30));
            final boxOp = Curves.easeOut.transform(_seg(t, 0.00, 0.18));
            final logo = Curves.easeOutCubic.transform(_seg(t, 0.28, 0.58));
            final title = Curves.easeOutCubic.transform(_seg(t, 0.52, 0.78));
            final sub = Curves.easeOut.transform(_seg(t, 0.66, 0.92));
            return Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.15),
                      radius: 0.95,
                      colors: [op(C.bg2, 0.95 * boxOp), C.bg],
                    ),
                  ),
                ),
                Center(
                  child: Opacity(
                    opacity: boxOp,
                    child: Transform.scale(
                      scale: 0.6 + 0.4 * boxIn,
                      child: LiquidGlass(
                        width: 240,
                        height: 240,
                        radius: 60,
                        tint: 0.12,
                        blur: 26,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Opacity(
                                opacity: logo,
                                child: Transform.scale(
                                  scale: 0.7 + 0.3 * logo,
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/logo.png',
                                      width: 116,
                                      height: 116,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox(width: 116, height: 116),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Opacity(
                                opacity: title,
                                child: Transform.translate(
                                  offset: Offset(0, (1 - title) * 10),
                                  child: const Text(
                                    'SoundXs',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white,
                                      letterSpacing: -0.4,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Opacity(
                                opacity: sub,
                                child: const Text(
                                  'FEEL THE MUSIC',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: C.sub,
                                    letterSpacing: 4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
