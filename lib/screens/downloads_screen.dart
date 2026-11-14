import 'dart:io';
import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/download_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';
import '../widgets/track_tile.dart';

/// Downloaded Music: antrian unduhan + semua lagu offline.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key, required this.onPlay});
  final void Function(Track, List<Track>) onPlay;

  String _dur(int ms) {
    if (ms <= 0) return '';
    final s = (ms / 1000).round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Hapus semua unduhan?'),
        content: const Text('Semua lagu offline dan unduhan yang sedang berjalan akan dihapus dari perangkat ini.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus semua')),
        ],
      ),
    );
    if (ok == true) await downloads.removeAll();
  }

  Future<void> _confirmDelete(BuildContext context, DlItem it) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Hapus unduhan?'),
        content: Text('"${it.track.title}" akan dihapus dari perangkat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true) await downloads.remove(it.track.id);
  }

  Widget _cover(DlItem it, double size) {
    final p = it.coverPath;
    if (p != null && File(p).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(File(p), width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 3).round()),
      );
    }
    return CoverImage(url: it.track.coverUrl, size: size, radius: 14);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.bg2, C.bg]),
        ),
        child: SafeArea(
          bottom: false,
          child: AnimatedBuilder(
            animation: downloads,
            builder: (context, _) {
              final done = downloads.completed;
              final active = downloads.active;
              final doneTracks = done.map((e) => e.track).toList();
              return ListView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: kBottomSpace),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => Navigator.of(context).pop()),
                      const Spacer(),
                      if (done.isNotEmpty || active.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => _confirmDeleteAll(context),
                          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                          label: const Text('Hapus semua'),
                        ),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                    child: const Text('Downloaded Music',
                        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Text('${done.length} lagu • ${fmtBytes(downloads.totalBytes)}',
                        style: const TextStyle(color: C.dim, fontSize: 13)),
                  ),
                  if (done.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: Row(children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: C.teal),
                          onPressed: () {
                            if (audioHandler.shuffleOn.value) audioHandler.toggleShuffle();
                            onPlay(doneTracks.first, doneTracks);
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Putar offline'),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            if (!audioHandler.shuffleOn.value) audioHandler.toggleShuffle();
                            onPlay(doneTracks.first, doneTracks);
                          },
                          icon: const Icon(Icons.shuffle_rounded),
                          label: const Text('Acak'),
                        ),
                      ]),
                    ),
                  if (active.isNotEmpty) ...[
                    _section('Unduhan'),
                    for (final it in active) _activeTile(context, it),
                  ],
                  if (done.isNotEmpty) ...[
                    _section('Tersimpan di perangkat'),
                    for (final it in done)
                      TrackTile(
                        track: it.track,
                        showDownload: false,
                        subtitle: [it.track.artist, _dur(it.track.durationMs), fmtBytes(it.sizeBytes)]
                            .where((e) => e.isNotEmpty)
                            .join(' • '),
                        onTap: () => onPlay(it.track, doneTracks),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white54, size: 20),
                          onPressed: () => _confirmDelete(context, it),
                        ),
                      ),
                  ],
                  if (done.isEmpty && active.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'Belum ada lagu yang diunduh. Tekan ikon unduh pada lagu yang diizinkan penyedia untuk memutarnya tanpa internet.',
                        style: TextStyle(color: C.dim, height: 1.5),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
      );

  Widget _activeTile(BuildContext context, DlItem it) {
    String status;
    switch (it.status) {
      case DlStatus.queued:
        status = 'Menunggu';
        break;
      case DlStatus.running:
        final pct = it.progress == null ? '' : '${(it.progress! * 100).round()}% • ';
        final size = it.total > 0 ? '${fmtBytes(it.received)} / ${fmtBytes(it.total)}' : fmtBytes(it.received);
        status = 'Berjalan • $pct$size • ${fmtBytes(it.speed)}/s';
        break;
      case DlStatus.paused:
        status = 'Dijeda • ${fmtBytes(it.received)}';
        break;
      case DlStatus.failed:
        status = 'Gagal: ${it.error ?? 'tidak diketahui'}';
        break;
      case DlStatus.done:
        status = 'Selesai';
        break;
    }
    final failed = it.status == DlStatus.failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: op(Colors.white, 0.05), borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Row(children: [
            _cover(it, 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(it.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: failed ? Colors.redAccent : C.dim, fontSize: 11.5)),
              ]),
            ),
            if (it.status == DlStatus.running)
              IconButton(icon: const Icon(Icons.pause_rounded), onPressed: () => downloads.pause(it.track.id)),
            if (it.status == DlStatus.paused)
              IconButton(icon: const Icon(Icons.play_arrow_rounded), onPressed: () => downloads.resume(it.track.id)),
            if (failed) IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => downloads.retry(it.track.id)),
            IconButton(
              tooltip: 'Batalkan',
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: () => downloads.cancel(it.track.id),
            ),
          ]),
          if (it.status == DlStatus.running || it.status == DlStatus.paused || it.status == DlStatus.queued)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: it.status == DlStatus.queued ? 0 : it.progress,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(C.mint),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
