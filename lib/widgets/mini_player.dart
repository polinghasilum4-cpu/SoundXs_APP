import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';
import 'liquid_glass.dart';
import 'press_scale.dart';

/// Pemutar mini melayang di atas navigasi. Geser ke samping = stop & tutup.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.track, required this.onTap});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = audioHandler;
    return Dismissible(
      key: ValueKey('mini_${track.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => h.stop(),
      child: PressScale(
        onTap: onTap,
        scale: 0.985,
        child: LiquidGlass(
          radius: 26,
          height: 68,
          tint: 0.12,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: StreamBuilder<Duration>(
                  stream: h.slowPosition,
                  builder: (_, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final total = h.player.duration?.inMilliseconds ?? track.durationMs;
                    final p = total <= 0 ? 0.0 : (pos.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
                    return LinearProgressIndicator(
                      value: p,
                      minHeight: 2.5,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(C.mint),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                child: Row(
                  children: [
                    CoverImage(url: track.coverUrl, size: 46, radius: 14),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: C.dim, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white70, size: 24),
                      onPressed: h.skipToPrevious,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                    StreamBuilder<bool>(
                      stream: h.player.playingStream,
                      initialData: h.player.playing,
                      builder: (_, snap) {
                        final playing = snap.data ?? false;
                        return GestureDetector(
                          onTap: playing ? h.pause : h.play,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Icon(
                              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 24,
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white70, size: 24),
                      onPressed: h.skipToNext,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
