import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../globals.dart';
import '../models/track.dart';
import '../screens/artist_screen.dart';
import '../services/audio_handler.dart';
import '../services/download_manager.dart';
import '../services/play_helper.dart';
import '../theme/app_theme.dart';
import 'download_button.dart';

const _sheetShape = RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28)));

String _tempoLabel(double v) => 'x${v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '')}';

String _hz(double hz) => hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz % 1000 == 0 ? 0 : 1)} kHz' : '${hz.round()} Hz';

/// Menu tambahan pemutar: volume, lihat artis, unduh, gaya suara, tempo/nada, EQ, sleep timer.
Future<void> showPlayerMenu(BuildContext context, Track t) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: _sheetShape,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, scroll) => _PlayerMenu(track: t, parent: context, scroll: scroll),
    ),
  );
}

class _PlayerMenu extends StatelessWidget {
  const _PlayerMenu({required this.track, required this.parent, required this.scroll});
  final Track track;
  final BuildContext parent;
  final ScrollController scroll;

  Widget _item(IconData icon, String title, String? sub, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: sub == null ? null : Text(sub, style: const TextStyle(color: C.dim, fontSize: 12.5)),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    final h = audioHandler;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 32),
      children: [
        Center(
          child: Container(
              width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: StreamBuilder<double>(
            stream: h.player.volumeStream,
            initialData: h.player.volume,
            builder: (_, snap) => Row(children: [
              const Icon(Icons.volume_down_rounded, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: (snap.data ?? 1.0).clamp(0.0, 1.0).toDouble(),
                  onChanged: (v) => h.setVolume(v),
                ),
              ),
              const Icon(Icons.volume_up_rounded, color: Colors.white54),
            ]),
          ),
        ),
        const Divider(color: Colors.white12),
        if (track.permalinkUrl.isNotEmpty)
          _item(Icons.link_rounded, 'Salin link', null, () async {
            await Clipboard.setData(ClipboardData(text: track.permalinkUrl));
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(parent)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Link disalin'), behavior: SnackBarBehavior.floating));
            }
          }),
        _item(Icons.person_search_rounded, 'Lihat artis', track.artist, () {
          Navigator.pop(context);
          Navigator.of(parent).push(MaterialPageRoute<void>(
            builder: (_) => ArtistScreen(
              name: track.artist,
              artistId: track.artistId,
              avatar: track.artistAvatar,
              onPlay: playFromList,
            ),
          ));
        }),
        AnimatedBuilder(
          animation: downloads.watch(track.id),
          builder: (_, __) {
            final it = downloads.itemFor(track.id);
            final reason = downloads.blockReason(track);
            String sub;
            if (it?.status == DlStatus.done) {
              sub = 'Sudah diunduh, bisa diputar offline';
            } else if (it != null) {
              sub = 'Sedang diproses, lihat di Library > Downloaded Music';
            } else {
              sub = reason ?? 'Simpan untuk diputar tanpa internet';
            }
            return _item(
              it?.status == DlStatus.done ? Icons.download_done_rounded : Icons.download_rounded,
              'Unduh',
              sub,
              () => requestDownload(context, track),
            );
          },
        ),
        const Divider(color: Colors.white12),
        _item(Icons.equalizer_rounded, 'Ekualiser', 'Atur bass dan frekuensi', () => showEqualizerSheet(context)),
        _item(Icons.graphic_eq_rounded, 'Gaya suara', 'Sped up, slowed + reverb, lo-fi, 8D, dan lainnya',
            () => showStyleDialog(context)),
        _item(Icons.tune_rounded, 'Lanjutan', 'Sesuaikan tempo dan nada lagu', () => showTempoPitchDialog(context)),
        ValueListenableBuilder<DateTime?>(
          valueListenable: h.sleepEnd,
          builder: (_, end, __) => ValueListenableBuilder<bool>(
            valueListenable: h.sleepAtTrackEnd,
            builder: (_, atEnd, __) => _item(
              Icons.bedtime_rounded,
              'Sleep timer',
              atEnd ? 'Berhenti setelah lagu ini' : (end != null ? 'Berhenti pukul ${_clock(end)}' : 'Mati'),
              () => showSleepDialog(context),
            ),
          ),
        ),
      ],
    );
  }
}

String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

// ───────────────────────── Gaya suara ─────────────────────────
Future<void> showStyleDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Gaya suara'),
      content: SizedBox(
        width: double.maxFinite,
        child: ValueListenableBuilder<String>(
          valueListenable: audioHandler.style,
          builder: (_, cur, __) => ListView(
            shrinkWrap: true,
            children: [
              for (final s in kSoundStyleList)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(cur == s.key ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: cur == s.key ? C.mint : Colors.white54),
                  title: Text(s.label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: Text(s.desc, style: const TextStyle(color: C.dim, fontSize: 12)),
                  onTap: () => audioHandler.setStyle(s.key),
                ),
              ValueListenableBuilder<String?>(
                valueListenable: audioHandler.fxNotice,
                builder: (_, n, __) => n == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(n, style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

// ───────────────────────── Tempo & nada ─────────────────────────
Future<void> showTempoPitchDialog(BuildContext context) {
  Widget stepper(IconData icon, Widget value, VoidCallback minus, VoidCallback plus) => Row(
        children: [
          Icon(icon, color: Colors.white70),
          const Spacer(),
          IconButton(icon: const Icon(Icons.remove_rounded), onPressed: minus),
          SizedBox(width: 64, child: Center(child: value)),
          IconButton(icon: const Icon(Icons.add_rounded), onPressed: plus),
        ],
      );
  final h = audioHandler;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Tempo dan Nada'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: h.tempo,
            builder: (_, v, __) => stepper(
              Icons.speed_rounded,
              Text(_tempoLabel(v), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              () => h.setTempo(v - 0.05),
              () => h.setTempo(v + 0.05),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: h.pitchSemi,
            builder: (_, v, __) => stepper(
              Icons.music_note_rounded,
              Text(v > 0 ? '+$v' : '$v', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              () => h.setPitchSemitones(v - 1),
              () => h.setPitchSemitones(v + 1),
            ),
          ),
          const SizedBox(height: 6),
          const Text('Tempo 0.5x–2.0x, nada -12 sampai +12 semiton. Keduanya diatur terpisah.',
              style: TextStyle(color: C.dim, fontSize: 11.5)),
        ],
      ),
      actions: [
        TextButton(onPressed: h.resetTempoPitch, child: const Text('Atur ulang')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
      ],
    ),
  );
}

// ───────────────────────── Sleep timer ─────────────────────────
Future<void> showSleepDialog(BuildContext context) {
  final h = audioHandler;
  const mins = [5, 10, 15, 30, 45, 60];
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      title: const Text('Sleep timer'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final m in mins)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('$m menit'),
                onTap: () {
                  h.setSleepTimer(Duration(minutes: m));
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Setelah lagu ini selesai'),
              onTap: () {
                h.setSleepAtTrackEnd(true);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Matikan timer', style: TextStyle(color: C.mint)),
              onTap: () {
                h.cancelSleep();
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    ),
  );
}

// ───────────────────────── Equalizer ─────────────────────────
Future<void> showEqualizerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: C.surface,
    shape: _sheetShape,
    builder: (_) => const _EqSheet(),
  );
}

class _EqSheet extends StatefulWidget {
  const _EqSheet();

  @override
  State<_EqSheet> createState() => _EqSheetState();
}

class _EqSheetState extends State<_EqSheet> {
  late List<double> _g = List<double>.of(audioHandler.eqGains);

  @override
  Widget build(BuildContext context) {
    final h = audioHandler;
    return SafeArea(
      child: ValueListenableBuilder<List<EqBandInfo>>(
        valueListenable: h.eqBands,
        builder: (_, bands, __) {
          if (bands.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Ekualiser belum siap. Putar sebuah lagu dulu. Ekualiser hanya tersedia di Android.',
                style: TextStyle(color: C.dim, height: 1.5),
              ),
            );
          }
          if (_g.length != bands.length) _g = List<double>.of(h.eqGains);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  const Expanded(
                    child: Text('Ekualiser', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: h.eqEnabled,
                    builder: (_, on, __) => Switch(value: on, onChanged: h.setEqEnabled),
                  ),
                ]),
                for (var i = 0; i < bands.length; i++)
                  Row(children: [
                    SizedBox(width: 56, child: Text(_hz(bands[i].freqHz), style: const TextStyle(color: C.sub, fontSize: 12))),
                    Expanded(
                      child: Slider(
                        min: bands[i].minDb,
                        max: bands[i].maxDb,
                        value: _g[i].clamp(bands[i].minDb, bands[i].maxDb).toDouble(),
                        onChanged: (v) => setState(() => _g[i] = v),
                        onChangeEnd: (v) {
                          if (!h.eqEnabled.value) h.setEqEnabled(true);
                          h.setEqGain(i, v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text('${_g[i].toStringAsFixed(1)} dB',
                          textAlign: TextAlign.right, style: const TextStyle(color: C.dim, fontSize: 11.5)),
                    ),
                  ]),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      h.resetEq();
                      setState(() => _g = List<double>.filled(bands.length, 0));
                    },
                    child: const Text('Atur ulang'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
