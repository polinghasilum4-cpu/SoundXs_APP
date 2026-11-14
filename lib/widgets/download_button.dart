import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';

/// Memasukkan lagu ke antrian unduh dan memberi umpan balik yang jelas (termasuk alasan jika ditolak).
void requestDownload(BuildContext context, Track t) {
  final m = ScaffoldMessenger.of(context);
  final reason = downloads.enqueue(t);
  final msg = reason ?? (downloads.isDone(t.id) ? 'Sudah diunduh' : 'Mengunduh "${t.title}"');
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Tombol unduh per lagu. Hanya rebuild saat status lagu INI berubah.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.track, this.size = 22});

  final Track track;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (track.kind != ItemKind.track) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: downloads.watch(track.id),
      builder: (context, _) {
        final it = downloads.itemFor(track.id);
        final box = size + 14;
        Widget icon;
        VoidCallback onTap;
        String tip;

        switch (it?.status) {
          case DlStatus.done:
            icon = Icon(Icons.check_circle_rounded, color: C.mint, size: size);
            onTap = () => requestDownload(context, track);
            tip = 'Sudah diunduh';
            break;
          case DlStatus.running:
            icon = Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(value: it!.progress, strokeWidth: 2.5, color: C.mint),
              ),
              Icon(Icons.pause_rounded, size: size * 0.55, color: Colors.white70),
            ]);
            onTap = () => downloads.pause(track.id);
            tip = 'Jeda unduhan';
            break;
          case DlStatus.queued:
            icon = Icon(Icons.hourglass_top_rounded, color: Colors.white54, size: size);
            onTap = () => downloads.cancel(track.id);
            tip = 'Batalkan antrian';
            break;
          case DlStatus.paused:
            icon = Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(value: it!.progress, strokeWidth: 2.5, color: Colors.white38),
              ),
              Icon(Icons.play_arrow_rounded, size: size * 0.7, color: Colors.white70),
            ]);
            onTap = () => downloads.resume(track.id);
            tip = 'Lanjutkan unduhan';
            break;
          case DlStatus.failed:
            icon = Icon(Icons.refresh_rounded, color: Colors.redAccent, size: size);
            onTap = () => downloads.retry(track.id);
            tip = 'Coba lagi';
            break;
          case null:
            final blocked = downloads.blockReason(track) != null;
            icon = Icon(Icons.download_rounded, color: blocked ? Colors.white24 : Colors.white70, size: size);
            onTap = () => requestDownload(context, track);
            tip = blocked ? 'Tidak bisa diunduh' : 'Unduh';
            break;
        }

        return Tooltip(
          message: tip,
          child: InkResponse(
            onTap: onTap,
            radius: box / 2,
            child: SizedBox(width: box, height: box, child: Center(child: icon)),
          ),
        );
      },
    );
  }
}
