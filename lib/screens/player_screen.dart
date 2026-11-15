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
  bool _downloading = false;

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
    _lyrics = _api.getLyrics(t).catchError((_) => const LyricsResult([], false));
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
            icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70),
            onPressed: _showQueue,
          ),
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
            return const Center(child: Text('Lirik tidak tersedia', style: TextStyle(color: C.dim)));
          }
          return SyncedLyrics(
            key: ValueKey('lyrics_${t.id}'),
            lines: r.lines,
            synced: r.synced,
            current: audioHandler.player.position,
            position: audioHandler.player.positionStream,
            onSeek: (d) => audioHandler.seek(d),
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
                  offline ? 'Tersimpan' : (_downloading ? 'Mengunduh…' : 'Unduh'),
                  offline || _downloading ? null : () => _downloadOffline(t),
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

  Future<void> _downloadOffline(Track t) async {
    if (_downloading || store.isOffline(t.id)) return;
    setState(() => _downloading = true);
    try {
      Track src = t;
      try {
        final fresh = await _api.refresh(t);
        if (fresh != null && fresh.hasStream) src = fresh;
      } catch (_) {}
      if (!src.hasStream) throw Exception('Stream tidak tersedia');

      final proxyUrl = await _api.proxiedStream(src);
      if (proxyUrl.isEmpty) throw Exception('URL stream kosong');

      final headers = <String, String>{
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
      };

      Future<http.Response> get(String url, {int sec = 45}) => http
          .get(Uri.parse(url), headers: headers)
          .timeout(Duration(seconds: sec));

      final resp = await get(proxyUrl, sec: 60);
      if (resp.statusCode < 200 || resp.statusCode >= 400) {
        throw Exception('Server stream error (${resp.statusCode})');
      }

      final ctype = (resp.headers['content-type'] ?? '').toLowerCase();
      final head = resp.bodyBytes.length > 16
          ? String.fromCharCodes(resp.bodyBytes.take(16))
          : String.fromCharCodes(resp.bodyBytes);
      final isM3u = head.trimLeft().startsWith('#EXT') ||
          ctype.contains('mpegurl') ||
          ctype.contains('x-mpegurl');

      late Uint8List bytes;
      var outExt = 'm4a';

      if (!isM3u) {
        // Progressive (mp3/dll)
        bytes = resp.bodyBytes;
        if (ctype.contains('mpeg') || ctype.contains('mp3')) outExt = 'mp3';
      } else {
        // HLS SoundCloud: #EXT-X-MAP init.mp4 + dataXXX.m4s
        final playlistBody = resp.body;
        // URL final playlist (setelah redirect) dipakai resolve relatif — proxy sudah absolute
        final base = proxyUrl;

        final initUri = _pickMapUri(playlistBody);
        final segs = _pickAllSegmentsFromM3u8(playlistBody, base);
        if (segs.isEmpty && initUri == null) {
          // Coba nested media playlist
          final nested = _pickMediaFromM3u8(playlistBody, base);
          if (nested == null) throw Exception('Playlist HLS kosong');
          final nestedResp = await get(nested, sec: 60);
          final body2 = nestedResp.body;
          final init2 = _pickMapUri(body2);
          final segs2 = _pickAllSegmentsFromM3u8(body2, nested);
          if (segs2.isEmpty) throw Exception('Tidak ada segmen audio');
          bytes = await _downloadHlsParts(get, init2, segs2);
        } else {
          bytes = await _downloadHlsParts(get, initUri, segs);
        }
        outExt = 'm4a';
      }

      if (bytes.length < 30 * 1024) {
        throw Exception(
            'File terlalu kecil (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
      }

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/soundxs_offline');
      if (!await dir.exists()) await dir.create(recursive: true);
      final safeId = t.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${dir.path}/$safeId.$outExt');
      await file.writeAsBytes(bytes, flush: true);

      if (!await file.exists() || await file.length() < 30 * 1024) {
        throw Exception('Gagal menyimpan file ke disk');
      }

      store.markOffline(src, file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Lagu disimpan offline (${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengunduh: ${e.toString().replaceFirst('Exception: ', '')}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Unduh init (EXT-X-MAP) + semua segmen, gabung jadi satu file fMP4.
  Future<Uint8List> _downloadHlsParts(
    Future<http.Response> Function(String url, {int sec}) get,
    String? initUri,
    List<String> segs,
  ) async {
    // Batasi lagu sangat panjang agar tidak menggantung (≈15 menit @10s/segmen)
    final take = segs.length > 90 ? segs.sublist(0, 90) : segs;
    final buf = BytesBuilder(copy: false);

    if (initUri != null && initUri.isNotEmpty) {
      final r = await get(initUri, sec: 40);
      if (r.statusCode >= 200 && r.statusCode < 400) {
        buf.add(r.bodyBytes);
      }
    }

    var ok = 0;
    for (final seg in take) {
      try {
        final r = await get(seg, sec: 30);
        if (r.statusCode >= 200 && r.statusCode < 400 && r.bodyBytes.isNotEmpty) {
          buf.add(r.bodyBytes);
          ok++;
        }
      } catch (_) {}
    }
    if (ok == 0) throw Exception('Gagal mengunduh segmen audio');
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
      final abs = line.startsWith('http')
          ? line
          : Uri.parse(baseUrl).resolve(line).toString();
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
      final abs = line.startsWith('http')
          ? line
          : Uri.parse(baseUrl).resolve(line).toString();
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
