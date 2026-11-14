import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/perf.dart';
import '../globals.dart';
import '../models/track.dart';
import '../services/api_service.dart';
import '../services/audio_handler.dart';
import '../theme/app_theme.dart';
import '../widgets/cover_colors.dart';
import '../widgets/cover_image.dart';
import '../widgets/download_button.dart';
import '../widgets/player_sheets.dart';
import '../widgets/press_scale.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _api = ApiService();
  double? _drag; // posisi saat slider digeser (biar tidak "ditarik balik" stream posisi)
  Color _tint = C.teal;
  String _tintFor = '';

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

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final h = audioHandler;
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
                valueListenable: h.current,
                builder: (context, track, _) {
                  if (track == null) return const SizedBox.shrink();
                  return LayoutBuilder(
                    builder: (context, box) {
                      final cover = math.min(box.maxWidth - 56, box.maxHeight * 0.4).clamp(160.0, 420.0).toDouble();
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              children: [
                                _topBar(track),
                                const SizedBox(height: 8),
                                _cover(track, cover, lite),
                                const SizedBox(height: 22),
                                _titleRow(track),
                                const SizedBox(height: 6),
                                _seek(track),
                                _controls(),
                                const SizedBox(height: 6),
                                _volume(),
                                const SizedBox(height: 8),
                                _styles(),
                                const SizedBox(height: 10),
                                _bottomActions(track),
                                const SizedBox(height: 10),
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

  Widget _topBar(Track t) => Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text('Sedang diputar',
                textAlign: TextAlign.center,
                style: TextStyle(color: C.sub, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
          IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: () => showPlayerMenu(context, t)),
        ],
      );

  Widget _cover(Track t, double size, bool lite) {
    return StreamBuilder<bool>(
      stream: audioHandler.player.playingStream,
      initialData: audioHandler.player.playing,
      builder: (_, snap) {
        final playing = snap.data ?? false;
        return AnimatedScale(
          // ala Apple Music/Auralys: sampul mengecil saat pause
          scale: playing ? 1.0 : 0.9,
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

  Widget _titleRow(Track t) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.sub, fontSize: 14.5)),
              ],
            ),
          ),
          DownloadButton(track: t, size: 24),
          AnimatedBuilder(
            animation: store,
            builder: (_, __) {
              final liked = store.isLiked(t.id);
              return IconButton(
                icon: Icon(liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: liked ? C.mint : Colors.white70, size: 28),
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
            icon: Icon(m == SxRepeatMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                color: m == SxRepeatMode.off ? Colors.white54 : C.mint),
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
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.black, size: 40),
          ),
        );
      },
    );
  }

  Widget _styles() {
    final h = audioHandler;
    final styles = kSoundStyles.where((s) => s != 'bass' || SoundXsAudioHandler.supportsBass).toList();
    return SizedBox(
      height: 38,
      child: ValueListenableBuilder<String>(
        valueListenable: h.style,
        builder: (_, cur, __) => ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: styles.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final s = styles[i];
            final active = cur == s;
            return PressScale(
              onTap: () => h.setStyle(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? Colors.white : op(Colors.white, 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(s == '8d' ? '8D' : (s == 'concert' ? 'Konser' : (s == 'slowed' ? 'Slowed + reverb' : kSoundLabels[s]!)),
                    style: TextStyle(
                        color: active ? Colors.black : Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _volume() {
    final p = audioHandler.player;
    return StreamBuilder<double>(
      stream: p.volumeStream,
      initialData: p.volume,
      builder: (_, snap) => Row(
        children: [
          const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 20),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: SliderComponentShape.noOverlay,
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: (snap.data ?? 1.0).clamp(0.0, 1.0).toDouble(),
                onChanged: audioHandler.setVolume,
              ),
            ),
          ),
          const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 20),
        ],
      ),
    );
  }

  Widget _bottomActions(Track t) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            onPressed: () => _showLyrics(t),
            icon: const Icon(Icons.lyrics_rounded, size: 18),
            label: const Text('Lirik'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          TextButton.icon(
            onPressed: _showQueue,
            icon: const Icon(Icons.queue_music_rounded, size: 18),
            label: const Text('Antrian'),
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
          ),
          ValueListenableBuilder<DateTime?>(
            valueListenable: audioHandler.sleepEnd,
            builder: (_, end, __) => ValueListenableBuilder<bool>(
              valueListenable: audioHandler.sleepAtTrackEnd,
              builder: (_, atEnd, __) => TextButton.icon(
                onPressed: () => showSleepDialog(context),
                icon: Icon(Icons.bedtime_rounded, size: 18, color: (end != null || atEnd) ? C.mint : null),
                label: const Text('Timer'),
                style: TextButton.styleFrom(foregroundColor: (end != null || atEnd) ? C.mint : Colors.white70),
              ),
            ),
          ),
        ],
      );

  void _showLyrics(Track t) {
    final future = _api.getLyrics(t);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scroll) => FutureBuilder<String>(
          future: future,
          builder: (_, snap) {
            Widget body;
            if (snap.connectionState != ConnectionState.done) {
              body = const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: C.mint)),
              );
            } else {
              final txt = snap.hasError || (snap.data ?? '').trim().isEmpty ? 'Lirik tidak tersedia' : snap.data!;
              body = Text(txt, style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.7));
            }
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Text(t.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                body,
              ],
            );
          },
        ),
      ),
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
                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: active ? C.mint : Colors.white, fontWeight: FontWeight.w700)),
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
