import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/perf.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/press_scale.dart';

/// Tampilan di dalam player: Cover atau Lirik. Tab ketiga (Gaya) membuka sheet sendiri.
enum _PlayerView { cover, lyrics }

/// Deskripsi tiap gaya suara. Angkanya sama dengan mesin audio (audio_handler.dart).
const kStyleInfo = <String, String>{
  'normal': 'Suara asli tanpa efek',
  'spedup': 'Lebih cepat dan sedikit tinggi, 1.25x',
  'slowed': 'Lebih pelan dan rendah, 0.85x',
  'nightcore': 'Jauh lebih cepat dan tinggi, 1.4x',
  'bass': 'Dentuman bass ditebalkan',
};

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _api = ApiService();
  double? _drag; // posisi saat slider digeser (biar tidak ditarik balik stream posisi)
  Color _tint = C.teal;
  String _tintFor = '';
  _PlayerView _view = _PlayerView.cover;
  String _lyricsId = '';
  Future<String>? _lyrics;

  @override
  void initState() {
    super.initState();
    audioHandler.current.addListener(_onTrack);
    _onTrack();
  }

  @override
  void dispose() {
    audioHandler.current.removeListener(_onTrack);
    super.dispose();
  }

  void _onTrack() {
    final t = audioHandler.current.value;
    if (t == null) {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
      return;
    }
    if (_view == _PlayerView.lyrics) _ensureLyrics(t);
    if (t.coverUrl == _tintFor) return;
    _tintFor = t.coverUrl;
    final cached = CoverColors.peek(t.coverUrl);
    if (cached != null) {
      _tint = cached;
      return;
    }
    CoverColors.dominant(t.coverUrl).then((c) {
      if (mounted && _tintFor == t.coverUrl) setState(() => _tint = c);
    });
  }

  /// Lirik hanya diambil sekali per lagu. Lagu berganti -> ambil ulang.
  void _ensureLyrics(Track t) {
    if (_lyricsId == t.id && _lyrics != null) return;
    _lyricsId = t.id;
    _lyrics = _api.getLyrics(t).catchError((_) => '');
  }

  void _setView(_PlayerView v) {
    final t = audioHandler.current.value;
    if (t == null) return;
    if (v == _PlayerView.lyrics) _ensureLyrics(t);
    setState(() => _view = v);
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Perf.instance.lite,
      builder: (context, lite, _) {
        return Scaffold(
          backgroundColor: C.bg,
          body: AnimatedContainer(
            duration: lite ? Duration.zero : const Duration(milliseconds: 600),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [_tint, C.bg],
                stops: const [0.0, 0.85],
              ),
            ),
            child: SafeArea(
              child: ValueListenableBuilder<Track?>(
                valueListenable: audioHandler.current,
                builder: (context, track, _) {
                  if (track == null) return const SizedBox.shrink();
                  return LayoutBuilder(
                    builder: (context, box) {
                      final cover = math.min(box.maxWidth - 64, box.maxHeight * 0.40).clamp(180.0, 400.0).toDouble();
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                _topBar(),
                                const SizedBox(height: 10),
                                _segmented(),
                                const SizedBox(height: 18),
                                _artArea(track, cover, lite),
                                const SizedBox(height: 22),
                                _titleRow(track),
                                const SizedBox(height: 6),
                                _seek(track),
                                const SizedBox(height: 4),
                                _controls(),
                                const SizedBox(height: 16),
                                _bottomActions(),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _topBar() => Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'SEDANG DIPUTAR',
              textAlign: TextAlign.center,
              style: TextStyle(color: C.sub, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1.6),
            ),
          ),
          IconButton(icon: const Icon(Icons.queue_music_rounded), onPressed: _showQueue),
        ],
      );

  /// Segmen Cover | Lirik | Gaya, sama dengan tab di web.
  Widget _segmented() {
    return Center(
      child: LiquidGlass(
        radius: 999,
        tint: 0.08,
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _segItem('Cover', _view == _PlayerView.cover, () => _setView(_PlayerView.cover)),
            _segItem('Lirik', _view == _PlayerView.lyrics, () => _setView(_PlayerView.lyrics)),
            _segItem('Gaya', false, _showStyles, icon: Icons.graphic_eq_rounded),
          ],
        ),
      ),
    );
  }

  Widget _segItem(String label, bool active, VoidCallback onTap, {IconData? icon}) {
    return PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: active ? Colors.black : Colors.white70),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: active ? Colors.black : Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _artArea(Track t, double size, bool lite) {
    return SizedBox(
      width: size,
      height: size,
      child: AnimatedSwitcher(
        duration: lite ? Duration.zero : const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _view == _PlayerView.cover
            ? KeyedSubtree(key: const ValueKey('cover'), child: _cover(t, size, lite))
            : _lyricsBox(size),
      ),
    );
  }

  Widget _cover(Track t, double size, bool lite) {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      initialData: audioHandler.player.playing,
      builder: (_, snap) {
        final playing = snap.data ?? false;
        return AnimatedScale(
          // sampul mengecil sedikit saat pause
          scale: playing ? 1.0 : 0.92,
          duration: lite ? Duration.zero : const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: lite
                  ? null
                  : [BoxShadow(color: op(Colors.black, 0.45), blurRadius: 40, offset: const Offset(0, 18))],
            ),
            child: CoverImage(url: t.coverUrl, size: size, radius: 28),
          ),
        );
      },
    );
  }

  Widget _lyricsBox(double size) {
    return LiquidGlass(
      key: const ValueKey('lyrics'),
      radius: 28,
      width: size,
      height: size,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: FutureBuilder<String>(
        future: _lyrics,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.mint, strokeWidth: 2.5));
          }
          final txt = snap.hasError || (snap.data ?? '').trim().isEmpty ? 'Lirik tidak tersedia' : snap.data!;
          return SingleChildScrollView(
            child: Text(
              txt,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.8, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }

  Widget _titleRow(Track t) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: C.sub, fontSize: 14.5),
                ),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: store,
            builder: (_, __) {
              final liked = store.isLiked(t.id);
              return IconButton(
                icon: Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: liked ? C.mint : Colors.white70,
                  size: 28,
                ),
                onPressed: () => store.toggleLike(t),
              );
            },
          ),
        ],
      );

  Widget _seek(Track t) {
    final p = audioHandler.player;
    return StreamBuilder<Duration?>(
      stream: p.durationStream,
      initialData: p.duration,
      builder: (_, dsnap) {
        final totalMs = (dsnap.data?.inMilliseconds ?? 0) > 0 ? dsnap.data!.inMilliseconds : t.durationMs;
        final max = totalMs > 0 ? totalMs.toDouble() : 1.0;
        return StreamBuilder<Duration>(
          stream: p.positionStream,
          initialData: p.position,
          builder: (_, psnap) {
            final pos = (psnap.data ?? Duration.zero).inMilliseconds.toDouble();
            final value = (_drag ?? pos).clamp(0.0, max).toDouble();
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: value,
                    min: 0,
                    max: max,
                    onChangeStart: (v) => setState(() => _drag = v),
                    onChanged: (v) => setState(() => _drag = v),
                    onChangeEnd: (v) {
                      audioHandler.seek(Duration(milliseconds: v.round()));
                      setState(() => _drag = null);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(Duration(milliseconds: value.round())),
                          style: const TextStyle(color: C.dim, fontSize: 11.5)),
                      Text(_fmt(Duration(milliseconds: totalMs)),
                          style: const TextStyle(color: C.dim, fontSize: 11.5)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _controls() {
    final h = audioHandler;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: h.shuffleOn,
          builder: (_, on, __) => IconButton(
            icon: Icon(Icons.shuffle_rounded, color: on ? C.mint : Colors.white54),
            onPressed: h.toggleShuffle,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 42),
          onPressed: h.skipToPrevious,
        ),
        _playButton(),
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 42),
          onPressed: h.skipToNext,
        ),
        ValueListenableBuilder<SxRepeatMode>(
          valueListenable: h.repeatMode,
          builder: (_, m, __) => IconButton(
            icon: Icon(
              m == SxRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              color: m == SxRepeatMode.off ? Colors.white54 : C.mint,
            ),
            onPressed: h.cycleRepeat,
          ),
        ),
      ],
    );
  }

  Widget _playButton() {
    final h = audioHandler;
    return StreamBuilder<bool>(
      stream: h.player.playingStream,
      initialData: h.player.playing,
      builder: (_, snap) {
        final playing = snap.data ?? false;
        return PressScale(
          scale: 0.92,
          onTap: playing ? h.pause : h.play,
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.black,
              size: 40,
            ),
          ),
        );
      },
    );
  }

  Widget _bottomActions() => Center(
        child: PressScale(
          onTap: _showQueue,
          child: LiquidGlass(
            radius: 999,
            tint: 0.08,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.queue_music_rounded, color: Colors.white70, size: 18),
                SizedBox(width: 8),
                Text('Antrian', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );

  void _showStyles() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _StyleSheet(),
    );
  }

  void _showQueue() {
    final h = audioHandler;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scroll) {
          final q = h.queueList;
          return ValueListenableBuilder<Track?>(
            valueListenable: h.current,
            builder: (_, cur, __) => ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 32),
              itemCount: q.length,
              itemBuilder: (_, i) {
                final t = q[i];
                final active = cur?.id == t.id;
                return ListTile(
                  leading: CoverImage(url: t.coverUrl, size: 44, radius: 12),
                  title: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: active ? C.mint : Colors.white, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(t.artist, maxLines: 1, style: const TextStyle(color: C.dim)),
                  trailing: active ? const Icon(Icons.graphic_eq_rounded, color: C.mint) : null,
                  onTap: () => h.playQueueIndex(i),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Sheet "Gaya suara" (sama seperti di web): pilih gaya -> langsung berlaku ke lagu yang sedang diputar.
class _StyleSheet extends StatelessWidget {
  const _StyleSheet();

  @override
  Widget build(BuildContext context) {
    final h = audioHandler;
    final styles = kSoundStyles.where((s) => s != 'bass' || SoundXsAudioHandler.supportsBass).toList();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: LiquidGlass(
          radius: 30,
          tint: 0.14,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gaya suara',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              const Text('Efek diterapkan real-time ke lagu yang diputar',
                  style: TextStyle(color: C.sub, fontSize: 12.5)),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: h.style,
                builder: (_, cur, __) => Column(
                  children: [for (final s in styles) _row(s, cur == s)],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Oke'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String s, bool active) {
    return PressScale(
      onTap: () {
        HapticFeedback.selectionClick();
        audioHandler.setStyle(s);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: active ? C.mint : Colors.white38, width: 2),
              ),
              child: active
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(color: C.mint, shape: BoxShape.circle),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kSoundLabels[s]!,
                    style: TextStyle(
                      color: active ? C.mint : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  Text(kStyleInfo[s] ?? '', style: const TextStyle(color: C.dim, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
