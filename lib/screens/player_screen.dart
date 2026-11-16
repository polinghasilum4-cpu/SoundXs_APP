import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
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
import '../widgets/synced_lyrics.dart';
import 'track_list_screen.dart';

/// Tampilan di area utama: Cover atau Lirik. Tab ketiga (Gaya) membuka sheet sendiri.
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
  Future<LyricsResult>? _lyrics;
  bool _followLyrics = true;
  bool _showIntervals = false;
  bool _downloading = false;
  double _dlProgress = 0;

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
    final override = store.lyricsOverride(t.id);
    _lyrics = override == null
        ? _api.getLyrics(t).catchError((_) => const LyricsResult([], false))
        : Future.value(_plainLyrics(override));
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
                  // Area utama (cover / lirik) mengisi semua ruang kosong; kontrol selalu di bawah.
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Column(
                      children: [
                        _topBar(),
                        const SizedBox(height: 6),
                        _segmented(),
                        const SizedBox(height: 12),
                        Expanded(child: _artArea(track, lite)),
                        const SizedBox(height: 14),
                        _titleRow(track),
                        const SizedBox(height: 4),
                        _seek(track),
                        _controls(),
                        const SizedBox(height: 2),
                        _volume(),
                        const SizedBox(height: 12),
                        _bottomActions(track),
                      ],
                    ),
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
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'SEDANG DIPUTAR',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            onPressed: () {
              final t = audioHandler.current.value;
              if (t != null) _showContextMenu(t);
            },
          ),
        ],
      );

  void _showContextMenu(Track t) {
    if (_view == _PlayerView.lyrics) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: C.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, sheetSetState) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _lyricsAction(Icons.edit_rounded, 'Ubah', () {
                          Navigator.pop(ctx);
                          _editLyrics(t);
                        }),
                        _lyricsAction(Icons.refresh_rounded, 'Muat ulang', () {
                          Navigator.pop(ctx);
                          store.setLyricsOverride(t.id, null);
                          _refreshLyrics(t);
                        }),
                        _lyricsAction(Icons.search_rounded, 'Cari', () {
                          Navigator.pop(ctx);
                          _searchLyrics(t);
                        }),
                        _lyricsAction(Icons.copy_rounded, 'Salin', () {
                          Navigator.pop(ctx);
                          _copyLyrics(t);
                        }),
                      ],
                    ),
                    const Divider(height: 24),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.translate_rounded, color: Colors.white70),
                      title: const Text('Terjemahan lirik AI'),
                      subtitle: const Text('Belum tersedia di API SoundXs'),
                      trailing: const Switch(value: false, onChanged: null),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.subtitles_rounded, color: Colors.white70),
                      title: const Text('Ikuti posisi lirik'),
                      subtitle: const Text('Gulir otomatis mengikuti lagu'),
                      value: _followLyrics,
                      onChanged: (value) {
                        setState(() => _followLyrics = value);
                        sheetSetState(() {});
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
                      title: const Text('Tampilkan indikator interval'),
                      subtitle: const Text('Tandai jeda panjang antarbaris lirik'),
                      value: _showIntervals,
                      onChanged: (value) {
                        setState(() => _showIntervals = value);
                        sheetSetState(() {});
                      },
                    ),
                    const Divider(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.source_rounded, color: Colors.white70),
                      title: const Text('Sumber lirik'),
                      trailing: const Text('SoundXs', style: TextStyle(color: C.dim)),
                    ),
                    FutureBuilder<LyricsResult>(
                      future: _lyrics,
                      builder: (_, snap) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_rounded, color: Colors.white70),
                        title: const Text('Waktu lirik'),
                        trailing: Text(
                          snap.data?.synced == true ? 'Tersinkron' : 'Tidak disinkron',
                          style: const TextStyle(color: C.dim),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: CoverImage(url: t.coverUrl, size: 44, radius: 8),
              title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.share_rounded),
              title: const Text('Salin tautan lagu'),
              onTap: () {
                Navigator.pop(ctx);
                _copyLink(t);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_search_rounded),
              title: const Text('Lihat artis'),
              onTap: () {
                Navigator.pop(ctx);
                _openArtist(t);
              },
            ),
            if (t.albumTitle.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.album_rounded),
                title: const Text('Lihat album'),
                subtitle: Text(t.albumTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAlbum(t);
                },
              ),
            ListTile(
              leading: Icon(store.isLiked(t.id) ? Icons.library_add_check_rounded : Icons.library_add_rounded),
              title: Text(store.isLiked(t.id) ? 'Hapus dari pustaka' : 'Tambah ke pustaka'),
              onTap: () {
                store.toggleLike(t);
                Navigator.pop(ctx);
              },
            ),
            if (store.isOffline(t.id))
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Hapus unduhan'),
                onTap: () {
                  Navigator.pop(ctx);
                  _removeOffline(t);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _lyricsAction(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              height: 78,
              decoration: BoxDecoration(color: op(Colors.white, 0.06), borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white70, size: 23),
                  const SizedBox(height: 7),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      );

  LyricsResult _plainLyrics(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => LyricLine(startMs: -1, text: line))
        .toList();
    return LyricsResult(lines, false);
  }

  Future<void> _editLyrics(Track t) async {
    final existing = store.lyricsOverride(t.id);
    final current = existing ?? (await (_lyrics ?? _api.getLyrics(t))).lines.map((e) => e.text).join('\n');
    if (!mounted) return;
    final controller = TextEditingController(text: current);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Ubah lirik'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 14,
            keyboardType: TextInputType.multiline,
            style: const TextStyle(color: Colors.white, height: 1.35),
            decoration: const InputDecoration(hintText: 'Satu baris lirik per baris'),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: const Text('Pulihkan dari API')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Simpan')),
        ],
      ),
    );
    if (action == null || !mounted) {
      controller.dispose();
      return;
    }
    if (action == 'reset') {
      store.setLyricsOverride(t.id, null);
      _refreshLyrics(t);
    } else {
      store.setLyricsOverride(t.id, controller.text);
      setState(() {
        _lyricsId = t.id;
        _lyrics = Future.value(_plainLyrics(controller.text));
      });
    }
    controller.dispose();
  }

  Future<void> _searchLyrics(Track t) async {
    final title = TextEditingController(text: ApiService.cleanTitle(t.title));
    final artist = TextEditingController(text: t.artist);
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Cari lirik di SoundXs'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Judul lagu')),
            TextField(controller: artist, decoration: const InputDecoration(labelText: 'Artis')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cari')),
        ],
      ),
    );
    if (go == true && title.text.trim().isNotEmpty && mounted) {
      final query = Track(
        id: t.id,
        title: title.text.trim(),
        artist: artist.text.trim(),
        coverUrl: t.coverUrl,
        durationMs: t.durationMs,
      );
      final lookup = _api.getLyrics(query);
      setState(() {
        _lyricsId = t.id;
        _lyrics = lookup;
      });
      try {
        final result = await lookup;
        if (!mounted) {
          title.dispose();
          artist.dispose();
          return;
        }
        if (result.isEmpty) _snack('Lirik tidak ditemukan di SoundXs');
      } catch (_) {
        if (mounted) _snack('Pencarian lirik SoundXs gagal. Coba lagi.');
      }
    }
    title.dispose();
    artist.dispose();
  }

  void _openArtist(Track t) {
    final artist = Track(
      id: t.artistId,
      title: t.artist,
      artist: t.artist,
      coverUrl: t.coverUrl,
      kind: ItemKind.user,
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrackListScreen(
        title: t.artist,
        subtitle: 'Artis',
        coverUrl: t.coverUrl,
        loader: () => _api.getArtistTracks(artist),
        onPlay: (track, queue) {
          final index = queue.indexOf(track);
          audioHandler.setQueue(queue, index < 0 ? 0 : index);
        },
      ),
    ));
  }

  void _openAlbum(Track t) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TrackListScreen(
        title: t.albumTitle,
        subtitle: t.artist,
        coverUrl: t.coverUrl,
        loader: () => _api.getAlbumTracks(t),
        onPlay: (track, queue) {
          final index = queue.indexOf(track);
          audioHandler.setQueue(queue, index < 0 ? 0 : index);
        },
      ),
    ));
  }

  Future<void> _copyLyrics(Track t) async {
    final future = _lyrics;
    final result = future == null ? await _api.getLyrics(t) : await future;
    if (!mounted) return;
    if (result.isEmpty) {
      _snack('Lirik tidak tersedia untuk disalin');
      return;
    }
    await Clipboard.setData(ClipboardData(text: result.lines.map((line) => line.text).join('\n')));
    _snack('Lirik disalin');
  }

  void _refreshLyrics(Track t) {
    setState(() {
      _lyricsId = '';
      _lyrics = null;
      _ensureLyrics(t);
    });
  }

  Future<void> _removeOffline(Track t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Hapus unduhan?'),
        content: Text('“${t.title}” akan dihapus dari penyimpanan offline.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await store.removeOffline(t.id);
    _snack(deleted ? 'Unduhan dihapus' : 'File offline tidak dapat dihapus');
  }

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

  /// Mengisi sisa tinggi layar. Cover = persegi terbesar yang muat. Lirik = seluruh area.
  Widget _artArea(Track t, bool lite) {
    return AnimatedSwitcher(
      duration: lite ? Duration.zero : const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: LayoutBuilder(
        key: ValueKey(_view),
        builder: (context, c) {
          if (_view == _PlayerView.lyrics) {
            return SizedBox(width: c.maxWidth, height: c.maxHeight, child: _lyricsPanel(t));
          }
          final side = (math.min(c.maxWidth, c.maxHeight) * 0.96).clamp(120.0, 560.0).toDouble();
          return Center(child: _cover(t, side, lite));
        },
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

  Widget _lyricsPanel(Track t) {
    return LiquidGlass(
      key: const ValueKey('lyrics'),
      radius: 28,
      tint: 0.10,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: FutureBuilder<LyricsResult>(
        future: _lyrics,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: C.mint, strokeWidth: 2.5));
          }
          final r = snap.data;
          if (r == null || r.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Lirik tidak tersedia', style: TextStyle(color: C.dim)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _refreshLyrics(t),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Coba lagi'),
                  ),
                ],
              ),
            );
          }
          return SyncedLyrics(
            key: ValueKey('lyrics_${t.id}'),
            lines: r.lines,
            synced: r.synced,
            current: audioHandler.player.position,
            position: audioHandler.player.positionStream,
            onSeek: (d) => audioHandler.seek(d),
            followPosition: _followLyrics,
            showIntervals: _showIntervals,
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

  Widget _volume() {
    final p = audioHandler.player;
    return StreamBuilder<double>(
      stream: p.volumeStream,
      initialData: p.volume,
      builder: (_, snap) {
        final v = (snap.data ?? 1.0).clamp(0.0, 1.0).toDouble();
        return Row(
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
                child: Slider(value: v, min: 0, max: 1, onChanged: (x) => audioHandler.setVolume(x)),
              ),
            ),
            const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 20),
          ],
        );
      },
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onTap, {bool active = false}) {
    return PressScale(
      onTap: onTap ?? () {},
      child: Opacity(
        opacity: onTap == null && !active ? 0.55 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass(
              radius: 999,
              tint: active ? 0.22 : 0.08,
              width: 52,
              height: 44,
              child: Icon(icon, color: active ? C.mint : Colors.white70, size: 22),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active ? C.mint : Colors.white54,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActions(Track t) {
    return AnimatedBuilder(
      animation: store,
      builder: (_, __) {
        return ValueListenableBuilder<DateTime?>(
          valueListenable: audioHandler.sleepUntil,
          builder: (_, until, __) {
            final offline = store.isOffline(t.id);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionBtn(
                  Icons.lyrics_rounded,
                  'Lirik',
                  () => _setView(_view == _PlayerView.lyrics ? _PlayerView.cover : _PlayerView.lyrics),
                  active: _view == _PlayerView.lyrics,
                ),
                _actionBtn(Icons.queue_music_rounded, 'Antrian', _showQueue),
                _actionBtn(
                  offline ? Icons.download_done_rounded : Icons.download_rounded,
                  offline ? 'Tersimpan' : (_downloading ? '${(_dlProgress * 100).round()}%' : 'Unduh'),
                  _downloading ? null : (offline ? () => _removeOffline(t) : () => _downloadOffline(t)),
                  active: offline || _downloading,
                ),
                _actionBtn(Icons.share_rounded, 'Bagikan', () => _copyLink(t)),
                _actionBtn(Icons.bedtime_rounded, until == null ? 'Tidur' : 'Aktif', _showSleep,
                    active: until != null),
              ],
            );
          },
        );
      },
    );
  }

  void _copyLink(Track t) {
    final text = t.permalinkUrl.isNotEmpty ? t.permalinkUrl : '${t.artist} - ${t.title}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Disalin ke clipboard'), behavior: SnackBarBehavior.floating));
  }

  void _setProgress(double v) {
    if (!mounted) return;
    final clamped = math.min(1.0, math.max(0.0, v));
    if ((clamped - _dlProgress).abs() < 0.01 && clamped < 1.0) return;
    setState(() => _dlProgress = clamped);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  static const _dlHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  Future<http.Response> _dlGet(String url, {int sec = 45}) async {
    try {
      return await http.get(Uri.parse(url), headers: _dlHeaders).timeout(Duration(seconds: sec));
    } on TimeoutException {
      throw Exception('koneksi lambat saat mengunduh');
    } on SocketException {
      throw Exception('tidak ada koneksi internet');
    }
  }

  /// Track dari daftar biasanya sudah punya stream. Hanya cari ulang kalau belum punya.
  Future<Track> _resolveForDownload(Track t) async {
    if (t.hasStream) return t;
    final fresh = await _api.refresh(t).timeout(const Duration(seconds: 25), onTimeout: () => null);
    if (fresh != null && fresh.hasStream) return fresh;
    throw Exception('stream tidak tersedia');
  }

  Future<void> _downloadOffline(Track t) async {
    if (_downloading || store.isOffline(t.id)) return;
    setState(() {
      _downloading = true;
      _dlProgress = 0;
    });
    try {
      var src = await _resolveForDownload(t);
      Uint8List bytes = Uint8List(0);
      var outExt = 'm4a';
      Object? lastError;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final proxyUrl = await _api.proxiedStream(src);
          if (proxyUrl.isEmpty) throw Exception('URL stream kosong');
          final resp = await _dlGet(proxyUrl, sec: 60);
          if (resp.statusCode < 200 || resp.statusCode >= 400) {
            throw Exception('server stream error (${resp.statusCode})');
          }
          final ctype = (resp.headers['content-type'] ?? '').toLowerCase();
          final head = String.fromCharCodes(resp.bodyBytes.take(64)).trimLeft();
          if (ctype.contains('text/html') || ctype.contains('application/json') || head.startsWith('{')) {
            throw Exception('server tidak mengirim file audio');
          }
          final isM3u = head.startsWith('#EXT') || ctype.contains('mpegurl');
          bytes = isM3u ? await _downloadHls(resp, proxyUrl) : resp.bodyBytes;
          outExt = (!isM3u && (ctype.contains('mpeg') || ctype.contains('mp3'))) ? 'mp3' : 'm4a';
          if (bytes.length < 30 * 1024) {
            throw Exception('file terlalu kecil (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
          }
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          final message = e.toString().toLowerCase();
          if (attempt == 0 && !message.contains('enkripsi') && !message.contains('playlist hls kosong')) {
            final fresh = await _api.refresh(src).timeout(
              const Duration(seconds: 12),
              onTimeout: () => null,
            );
            if (fresh != null && fresh.hasStream && fresh.id == src.id) {
              src = fresh;
              continue;
            }
          }
          break;
        }
      }
      if (lastError != null) throw lastError!;

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/soundxs_offline');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeId = t.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${dir.path}/$safeId.$outExt');
      final tempFile = File('${file.path}.part');
      try {
        await tempFile.writeAsBytes(bytes, flush: true);
        if (await file.exists()) await file.delete();
        await tempFile.rename(file.path); // file parsial tidak pernah jadi offline
      } catch (_) {
        if (await tempFile.exists()) await tempFile.delete();
        rethrow;
      }

      store.markOffline(t, file.path);
      _snack('Lagu disimpan offline (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)');
    } on TimeoutException {
      _snack('Gagal mengunduh: koneksi lambat, coba lagi');
    } catch (e) {
      _snack('Gagal mengunduh: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  bool _hasEncryption(String body) =>
      RegExp(r'#EXT-X-KEY:.*METHOD=(?!NONE)', caseSensitive: false).hasMatch(body);

  /// Playlist HLS (langsung atau bertingkat) -> gabung init + semua segmen jadi satu fMP4.
  Future<Uint8List> _downloadHls(http.Response resp, String playlistUrl) async {
    var body = resp.body;
    var base = resp.request?.url.toString() ?? playlistUrl;
    if (_hasEncryption(body)) throw Exception('stream memakai enkripsi, belum didukung');

    if (_pickAllSegmentsFromM3u8(body, base).isEmpty) {
      final nested = _pickMediaFromM3u8(body, base);
      if (nested == null) throw Exception('playlist HLS kosong');
      final r2 = await _dlGet(nested, sec: 45);
      if (r2.statusCode < 200 || r2.statusCode >= 400) {
        throw Exception('gagal membuka playlist audio (${r2.statusCode})');
      }
      body = r2.body;
      if (_hasEncryption(body)) throw Exception('stream memakai enkripsi, belum didukung');
      base = r2.request?.url.toString() ?? nested;
    }

    final segs = _pickAllSegmentsFromM3u8(body, base);
    if (segs.isEmpty) throw Exception('tidak ada segmen audio');
    final initRaw = _pickMapUri(body);
    final initUrl = initRaw == null ? null : Uri.parse(base).resolve(initRaw).toString();
    return _downloadHlsParts(initUrl, segs);
  }

  /// Segmen diambil 6 sekaligus, tapi disusun ulang berdasarkan indeks -> urutan tetap benar.
  Future<Uint8List> _downloadHlsParts(String? initUrl, List<String> segs) async {
    if (segs.length > 1800) throw Exception('playlist terlalu besar atau tidak valid');
    final total = segs.length + (initUrl == null ? 0 : 1);
    var done = 0;

    Uint8List? init;
    if (initUrl != null) {
      final r = await _dlGet(initUrl, sec: 40);
      if (r.statusCode < 200 || r.statusCode >= 400 || r.bodyBytes.isEmpty) {
        throw Exception('gagal mengunduh bagian awal audio');
      }
      init = r.bodyBytes;
      done++;
      _setProgress(done / total);
    }

    final parts = List<Uint8List?>.filled(segs.length, null);
    const batch = 6;
    for (var s = 0; s < segs.length; s += batch) {
      final end = math.min(s + batch, segs.length);
      final responses = await Future.wait([for (var i = s; i < end; i++) _dlGet(segs[i], sec: 45)]);
      for (var k = 0; k < responses.length; k++) {
        final r = responses[k];
        if (r.statusCode < 200 || r.statusCode >= 400 || r.bodyBytes.isEmpty) {
          throw Exception('gagal mengunduh segmen ${s + k + 1}/${segs.length}');
        }
        parts[s + k] = r.bodyBytes;
        done++;
      }
      _setProgress(done / total);
    }

    final buf = BytesBuilder(copy: false);
    if (init != null) buf.add(init);
    for (final p in parts) {
      buf.add(p!);
    }
    return buf.toBytes();
  }

  /// URI dari #EXT-X-MAP:URI="..."
  String? _pickMapUri(String body) {
    final m = RegExp(r'#EXT-X-MAP:.*?URI="([^"]+)"').firstMatch(body);
    return m?.group(1);
  }

  String? _pickMediaFromM3u8(String body, String baseUrl) {
    final lines = body.split(RegExp(r'\r?\n'));
    final candidates = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final abs = Uri.parse(baseUrl).resolve(line).toString();
      candidates.add(abs);
    }
    if (candidates.isEmpty) return null;
    for (final u in candidates) {
      if (!u.toLowerCase().contains('.m3u8')) return u;
    }
    return candidates.last;
  }

  List<String> _pickAllSegmentsFromM3u8(String body, String baseUrl) {
    final lines = body.split(RegExp(r'\r?\n'));
    final out = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.toLowerCase().contains('.m3u8')) continue;
      final abs = Uri.parse(baseUrl).resolve(line).toString();
      out.add(abs);
    }
    return out;
  }

  void _showTempo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        title: const Text('Tempo dan Nada', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: ValueListenableBuilder<double>(
          valueListenable: audioHandler.tempo,
          builder: (_, v, __) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_rounded, color: Colors.white),
                onPressed: () => audioHandler.setTempo(v - 0.05),
              ),
              Text('x${v.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              IconButton(
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                onPressed: () => audioHandler.setTempo(v + 0.05),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => audioHandler.setTempo(1.0), child: const Text('Atur ulang')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showSleep() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: LiquidGlass(
            radius: 30,
            tint: 0.14,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Material(
              color: Colors.transparent,
              child: ValueListenableBuilder<DateTime?>(
                valueListenable: audioHandler.sleepUntil,
                builder: (_, until, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Timer tidur',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Text(
                      until == null
                          ? 'Musik akan berhenti otomatis setelah waktu yang dipilih.'
                          : 'Berhenti pukul ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(color: C.sub, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    for (final m in const [15, 30, 60])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('$m menit', style: const TextStyle(color: Colors.white)),
                        onTap: () {
                          audioHandler.setSleepTimer(Duration(minutes: m));
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Matikan timer', style: TextStyle(color: Colors.white)),
                      onTap: () {
                        audioHandler.setSleepTimer(null);
                        Navigator.of(ctx).pop();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

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

/// Sheet "Gaya suara": pilih gaya -> langsung berlaku ke lagu yang sedang diputar.
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
