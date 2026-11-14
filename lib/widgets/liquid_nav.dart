import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'liquid_glass.dart';

const _kNavItems = <(IconData, IconData, String)>[
  (Icons.home_rounded, Icons.home_outlined, 'Beranda'),
  (Icons.search_rounded, Icons.search_rounded, 'Cari'),
  (Icons.library_music_rounded, Icons.library_music_outlined, 'Library'),
  (Icons.person_rounded, Icons.person_outline_rounded, 'Profil'),
];

const double kNavHeight = 66;
const int _kTabs = 4;

/// Navigasi bawah liquid glass.
///  - Geser jari di bar: blob kaca ikut jalan, ngeregang sesuai kecepatan, lalu memantul ke tab terdekat.
///  - Saat [shrunk] = true (user scroll ke bawah) bar menyusut jadi bulet kecil berisi ikon tab aktif.
///    Ketuk bulet itu untuk membuka lagi.
class LiquidNav extends StatefulWidget {
  const LiquidNav({
    super.key,
    required this.index,
    required this.onChanged,
    this.shrunk = false,
    this.onExpand,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final bool shrunk;
  final VoidCallback? onExpand;

  @override
  State<LiquidNav> createState() => _LiquidNavState();
}

class _LiquidNavState extends State<LiquidNav> with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(mass: 1, stiffness: 460, damping: 30);

  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: widget.index.toDouble());
  double _slot = 80;
  bool _dragging = false;
  double _stretch = 0;

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiquidNav old) {
    super.didUpdateWidget(old);
    if (!_dragging && old.index != widget.index) {
      _springTo(widget.index.toDouble(), 0);
    }
  }

  void _springTo(double target, double velocity) {
    _pos.animateWith(SpringSimulation(_spring, _pos.value, target, velocity));
  }

  void _select(int i, double velocity) {
    if (i != widget.index) {
      HapticFeedback.selectionClick();
      widget.onChanged(i);
    }
    _springTo(i.toDouble(), velocity);
  }

  void _onTapUp(TapUpDetails d) {
    if (widget.shrunk) {
      widget.onExpand?.call();
      return;
    }
    final i = (d.localPosition.dx / _slot).floor().clamp(0, _kTabs - 1).toInt();
    _select(i, 0);
  }

  void _onDragStart(DragStartDetails _) {
    _dragging = true;
    _pos.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (widget.shrunk) return;
    _stretch = (d.delta.dx.abs() / 16).clamp(0.0, 0.12).toDouble();
    _pos.value = (_pos.value + d.delta.dx / _slot).clamp(0.0, _kTabs - 1.0).toDouble();
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    _stretch = 0;
    if (widget.shrunk) return;
    final v = (d.primaryVelocity ?? 0) / _slot;
    final target = (_pos.value + v * 0.15).round().clamp(0, _kTabs - 1).toInt();
    _select(target, v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final full = c.maxWidth;
        _slot = full / _kTabs;
        return Align(
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: widget.shrunk ? 1 : 0),
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final w = full + (kNavHeight - full) * t;
              return AnimatedBuilder(
                animation: _pos,
                builder: (context, _) => _bar(full, w, t),
              );
            },
          ),
        );
      },
    );
  }

  Widget _bar(double full, double w, double t) {
    final pos = _pos.value.clamp(0.0, _kTabs - 1.0).toDouble();
    final shift = (kNavHeight / 2 - (pos + 0.5) * _slot) * t;
    final blobW = (_slot - 12) + (kNavHeight - 10 - (_slot - 12)) * t;
    final blobLeft = (pos + 0.5) * _slot - blobW / 2;
    final s = _dragging
        ? _stretch
        : (_pos.velocity.abs() / 10).clamp(0.0, 0.12).toDouble();

    final content = ClipRRect(
      borderRadius: BorderRadius.circular(kNavHeight / 2),
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: full,
        maxWidth: full,
        minHeight: kNavHeight,
        maxHeight: kNavHeight,
        child: Transform.translate(
          offset: Offset(shift, 0),
          child: SizedBox(
            width: full,
            height: kNavHeight,
            child: Stack(
              children: [
                Positioned(
                  left: blobLeft,
                  top: 5,
                  width: blobW,
                  height: kNavHeight - 10,
                  child: Transform.scale(
                    scaleX: 1 + s,
                    scaleY: 1 - s * 0.45,
                    child: LiquidGlass(
                      radius: (kNavHeight - 10) / 2,
                      tint: 0.20,
                      blur: 14,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < _kTabs; i++) SizedBox(width: _slot, child: _item(i, pos, t)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: _onTapUp,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: SizedBox(
        width: w,
        height: kNavHeight,
        child: LiquidGlass(radius: kNavHeight / 2, tint: 0.10, child: content),
      ),
    );
  }

  Widget _item(int i, double pos, double t) {
    final near = (1 - (i - pos).abs()).clamp(0.0, 1.0).toDouble();
    final vis = ((1 - t) + t * near).clamp(0.0, 1.0).toDouble();
    final labelOp = (1 - t * 1.8).clamp(0.0, 1.0).toDouble();
    final col = Color.lerp(Colors.white54, C.mint, near)!;
    final it = _kNavItems[i];
    return Opacity(
      opacity: vis,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(near >= 0.5 ? it.$1 : it.$2, size: 24, color: col),
          const SizedBox(height: 2),
          Opacity(
            opacity: labelOp,
            child: Text(
              it.$3,
              style: TextStyle(
                fontSize: 10,
                color: col,
                fontWeight: near >= 0.5 ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
