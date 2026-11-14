import 'package:flutter/material.dart';
import '../globals.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import 'cover_image.dart';
import 'press_scale.dart';

/// Baris lagu/playlist/artis. Tanpa BackdropFilter (penyebab utama lag di list panjang).
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.rank,
    this.trailing,
    this.subtitle,
  });

  final Track track;
  final VoidCallback onTap;
  final int? rank;
  final Widget? trailing;
  final String? subtitle;

  String get _sub {
    if (subtitle != null) return subtitle!;
    if (track.kind == ItemKind.playlist) {
      return track.trackCount > 0 ? '${track.artist} • ${track.trackCount} lagu' : track.artist;
    }
    if (track.kind == ItemKind.user) return 'Artis';
    return track.artist;
  }

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: ValueListenableBuilder<Track?>(
          valueListenable: audioHandler.current,
          builder: (context, cur, _) {
            final active = track.kind == ItemKind.track && cur?.id == track.id;
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: active ? op(C.teal, 0.22) : op(Colors.white, 0.05),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  if (rank != null)
                    SizedBox(
                      width: 30,
                      child: Text(
                        '$rank',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: rank! <= 3 ? C.mint : C.dim,
                        ),
                      ),
                    ),
                  CoverImage(
                    url: track.coverUrl,
                    size: 52,
                    radius: 14,
                    circle: track.kind == ItemKind.user,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? C.mint : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: C.dim, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (active) const Icon(Icons.graphic_eq_rounded, color: C.mint, size: 20),
                  if (trailing != null) trailing!,
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
