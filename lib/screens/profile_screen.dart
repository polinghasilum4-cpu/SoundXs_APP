import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/perf.dart';
import '../globals.dart';
import '../theme/app_theme.dart';
import '../widgets/equalizer_bars.dart';
import '../widgets/press_scale.dart';
import 'wrapped_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isIos => !kIsWeb && Platform.isIOS;

  Future<void> _toggleIsland(BuildContext context, bool v) async {
    if (v && _isAndroid && !await island.hasPermission()) {
      if (!context.mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: C.surface,
          title: const Text('Izin tampil di atas aplikasi lain'),
          content: const Text(
              'Dynamic Island butuh izin "Tampilkan di atas aplikasi lain" supaya bisa melayang di dekat kamera saat kamu membuka aplikasi lain.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Buka pengaturan')),
          ],
        ),
      );
      if (ok != true) return;
      await island.requestPermission();
      if (!await island.hasPermission()) return; // user belum mengizinkan
    }
    store.setIsland(on: v);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          return ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, kBottomSpace),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 16, 4, 16),
                child: Text('Kamu', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
              ),
              Row(children: [
                Expanded(child: _statCard('${store.totalPlays}', 'Lagu diputar')),
                const SizedBox(width: 12),
                Expanded(child: _statCard('${store.liked.length}', 'Disukai')),
              ]),
              const SizedBox(height: 12),
              _tile(
                icon: Icons.auto_awesome_rounded,
                title: 'SoundXs Wrapped',
                subtitle: 'Ringkasan lagu & artis favoritmu',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WrappedScreen())),
              ),

              _header('Dynamic Island'),
              _islandPreview(),
              const SizedBox(height: 10),
              _card([
                SwitchListTile(
                  value: store.islandOn,
                  onChanged: (v) => _toggleIsland(context, v),
                  activeColor: C.mint,
                  title: const Text('Di layar', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    _isIos
                        ? 'Pakai Live Activity. Tampil di Dynamic Island iPhone 14 Pro ke atas, dan di Lock Screen untuk iPhone lain.'
                        : _isAndroid
                            ? 'Pil melayang di dekat kamera saat kamu keluar dari aplikasi. Pencet untuk buka kontrol lagu.'
                            : 'Hanya tersedia di Android & iOS.',
                    style: const TextStyle(color: C.dim, fontSize: 12),
                  ),
                ),
                if (_isAndroid) ...[
                  SwitchListTile(
                    value: store.islandPop,
                    onChanged: store.islandOn ? (v) => store.setIsland(pop: v) : null,
                    activeColor: C.mint,
                    title: const Text('Kartu diperluas', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Melebar otomatis sebentar saat ganti lagu',
                        style: TextStyle(color: C.dim, fontSize: 12)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Gaya', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 'classic', label: Text('Klasik')),
                          ButtonSegment(value: 'curved', label: Text('Kelengkungan sudut')),
                        ],
                        selected: {store.islandStyle},
                        onSelectionChanged: (s) => store.setIsland(style: s.first),
                      ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Posisi vertikal: ${store.islandOffset} dp',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Slider(
                        value: store.islandOffset.toDouble(),
                        min: 0,
                        max: 60,
                        divisions: 60,
                        activeColor: C.mint,
                        onChanged: (v) => store.setIsland(offset: v.round()),
                      ),
                      const Text('Geser kalau pil belum pas dengan kamera depan HP-mu.',
                          style: TextStyle(color: C.dim, fontSize: 12)),
                    ]),
                  ),
                ],
              ]),

              _header('Performa'),
              _card([
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Auto')),
                        ButtonSegment(value: 1, label: Text('Hemat')),
                        ButtonSegment(value: 2, label: Text('Penuh')),
                      ],
                      selected: {store.perfMode},
                      onSelectionChanged: (s) {
                        store.setPerfMode(s.first);
                        Perf.instance.setMode(PerfMode.values[s.first]);
                      },
                    ),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<bool>(
                      valueListenable: Perf.instance.lite,
                      builder: (_, lite, __) => Text(
                        store.perfMode == 0
                            ? 'Auto: efek blur & animasi mati sendiri kalau HP terasa berat. Sekarang: ${lite ? 'hemat' : 'penuh'}.'
                            : store.perfMode == 1
                                ? 'Hemat: tanpa blur & bayangan. Paling ringan untuk HP kentang.'
                                : 'Penuh: semua efek kaca & animasi aktif.',
                        style: const TextStyle(color: C.dim, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ]),
                ),
              ]),

              _header('Data'),
              _tile(
                icon: Icons.delete_rounded,
                title: 'Hapus riwayat & statistik',
                subtitle: 'Lagu disukai tidak ikut terhapus',
                onTap: store.clearHistory,
              ),
              const SizedBox(height: 24),
              const Center(child: Text('SoundXs v1.1', style: TextStyle(color: C.dim, fontSize: 12))),
            ],
          );
        },
      ),
    );
  }

  Widget _islandPreview() {
    final curved = store.islandStyle == 'curved';
    return Container(
      height: 96,
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(color: op(Colors.white, 0.05), borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 170,
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: curved
              ? const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24))
              : BorderRadius.circular(19),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Icon(Icons.music_note_rounded, color: C.mint, size: 20),
            EqualizerBars(playing: true, height: 14, bars: 4, barWidth: 2.5),
          ],
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
        child: Text(t.toUpperCase(),
            style: const TextStyle(color: C.dim, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1)),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: op(Colors.white, 0.05), borderRadius: BorderRadius.circular(24)),
        child: Column(children: children),
      );

  Widget _statCard(String big, String label) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: op(Colors.white, 0.06), borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(big, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: C.mint)),
          Text(label, style: const TextStyle(color: C.dim, fontSize: 12)),
        ]),
      );

  Widget _tile({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: op(Colors.white, 0.05), borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: op(C.teal, 0.35), borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: C.mint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(subtitle, style: const TextStyle(color: C.dim, fontSize: 12)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.dim),
        ]),
      ),
    );
  }
}
