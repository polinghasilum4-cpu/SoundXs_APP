import 'package:flutter/material.dart';
import '../globals.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_image.dart';

/// Ringkasan dengar ala "Wrapped", dihitung dari statistik lokal.
class WrappedScreen extends StatelessWidget {
  const WrappedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final top = store.topPlayed(5);
    final artists = store.topArtists(3);
    final minutes = store.estimatedMinutes;
    final plays = store.totalPlays;

    return Scaffold(
      backgroundColor: C.bg,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B5F57), Color(0xFF0B1F20), C.bg],
          ),
        ),
        child: SafeArea(
          child: ListView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 40),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(height: 8),
              const Text('SoundXs\nWrapped',
                  style: TextStyle(fontSize: 46, height: 1.0, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 28),
              if (plays == 0)
                const Text('Belum ada data. Putar beberapa lagu dulu, nanti ringkasannya muncul di sini.',
                    style: TextStyle(color: C.sub, height: 1.5, fontSize: 15))
              else ...[
                Row(children: [
                  Expanded(child: _stat('$plays', 'lagu diputar')),
                  const SizedBox(width: 12),
                  Expanded(child: _stat('~$minutes', 'menit (perkiraan)')),
                ]),
                if (artists.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  const Text('Artis teratas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < artists.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 34,
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: i == 0 ? C.mint : C.dim)),
                        ),
                        Expanded(
                          child: Text(artists[i].key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        ),
                        Text('${artists[i].value}x', style: const TextStyle(color: C.dim)),
                      ]),
                    ),
                ],
                if (top.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text('Lagu teratas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  for (var i = 0; i < top.length; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        SizedBox(
                          width: 34,
                          child: Text('${i + 1}',
                              style: TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w900, color: i == 0 ? C.mint : C.dim)),
                        ),
                        CoverImage(url: top[i].track.coverUrl, size: 48, radius: 12),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(top[i].track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(top[i].track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: C.dim, fontSize: 12)),
                          ]),
                        ),
                        Text('${top[i].plays}x', style: const TextStyle(color: C.dim)),
                      ]),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String big, String label) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: op(Colors.white, 0.08), borderRadius: BorderRadius.circular(24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(big, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: C.mint)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: C.sub, fontSize: 12.5)),
        ]),
      );
}
