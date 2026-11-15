import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../globals.dart';
import '../models/track.dart';
import 'api_service.dart';

enum SxRepeatMode { off, all, one }

const kSoundStyles = ['normal', 'spedup', 'slowed', 'nightcore', 'bass'];
const kSoundLabels = {
  'normal': 'Normal',
  'spedup': 'Sped Up',
  'slowed': 'Slowed',
  'nightcore': 'Nightcore',
  'bass': 'Bass Boost',
};

class SoundXsAudioHandler extends BaseAudioHandler {
  SoundXsAudioHandler._(this._player, this._eq) {
    shuffleOn.addListener(refreshControls);
    _player.playbackEventStream.map(_transformEvent).listen(
          playbackState.add,
          onError: (Object e, StackTrace st) {},
        );
    // Notifikasi & panel media harus langsung berubah saat play/pause, tanpa nunggu event berikutnya.
    _player.playingStream.distinct().listen((_) {
      playbackState.add(_transformEvent(_player.playbackEvent));
    });
    _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
    // Durasi asli dari stream (lebih akurat dari metadata API) -> notifikasi ikut update.
    _player.durationStream.listen((d) {
      final item = mediaItem.value;
      if (d != null && item != null && item.duration != d) {
        mediaItem.add(item.copyWith(duration: d));
      }
    });
  }

  factory SoundXsAudioHandler.create() {
    if (!kIsWeb && Platform.isAndroid) {
      final eq = AndroidEqualizer();
      return SoundXsAudioHandler._(
        AudioPlayer(audioPipeline: AudioPipeline(androidAudioEffects: [eq])),
        eq,
      );
    }
    return SoundXsAudioHandler._(AudioPlayer(), null);
  }

  static bool get supportsBass => !kIsWeb && Platform.isAndroid;

  final AudioPlayer _player;
  final AndroidEqualizer? _eq;
  final ApiService _api = ApiService();

  List<Track> _queue = [];
  List<int> _order = [];
  int _pos = 0;
  int _token = 0;
  int _failStreak = 0;
  bool _shuffle = false;
  SxRepeatMode _repeat = SxRepeatMode.off;

  /// Tempo pengguna (0.5x - 2.0x), dikalikan dengan gaya suara.
  final ValueNotifier<double> tempo = ValueNotifier<double>(1.0);
  Timer? _sleepTimer;
  final ValueNotifier<DateTime?> sleepUntil = ValueNotifier<DateTime?>(null);

  /// Lagu yang sedang aktif. UI cukup listen ini (otomatis ikut saat auto-next).
  final ValueNotifier<Track?> current = ValueNotifier<Track?>(null);
  final ValueNotifier<bool> shuffleOn = ValueNotifier<bool>(false);
  final ValueNotifier<SxRepeatMode> repeatMode = ValueNotifier<SxRepeatMode>(SxRepeatMode.off);
  final ValueNotifier<String> style = ValueNotifier<String>('normal');
  final ValueNotifier<String?> errorMessage = ValueNotifier<String?>(null);

  /// Dipanggil setiap lagu benar-benar mulai diputar (untuk riwayat & statistik).
  void Function(Track track)? onTrackStarted;

  AudioPlayer get player => _player;
  List<Track> get queueList => List.unmodifiable(_queue);
  int get currentIndex => _order.isEmpty ? 0 : _order[_pos];

  late final Stream<Duration> slowPosition = _player
      .createPositionStream(
        minPeriod: const Duration(milliseconds: 500),
        maxPeriod: const Duration(milliseconds: 500),
      )
      .asBroadcastStream();

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: _controls(),
      // Agar tombol play/pause/next/prev muncul di notifikasi, lock screen, dan panel media HP
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updateTime: DateTime.now(),
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: currentIndex,
    );
  }

  /// Dipanggil dari main.dart: status disukai & aksi suka (sumber kebenaran tetap LibraryStore).
  bool Function(String id)? isLikedFn;
  void Function()? onLikeRequested;

  List<MediaControl> _controls() {
    final id = current.value?.id;
    final liked = id != null && (isLikedFn?.call(id) ?? false);
    return [
      MediaControl.skipToPrevious,
      _player.playing ? MediaControl.pause : MediaControl.play,
      MediaControl.skipToNext,
      MediaControl.custom(
        androidIcon: shuffleOn.value ? 'drawable/sx_ic_shuffle_on' : 'drawable/sx_ic_shuffle',
        label: shuffleOn.value ? 'Acak aktif' : 'Acak',
        name: 'sx_shuffle',
      ),
      MediaControl.custom(
        androidIcon: liked ? 'drawable/sx_ic_heart_on' : 'drawable/sx_ic_heart',
        label: liked ? 'Hapus dari disukai' : 'Suka',
        name: 'sx_like',
      ),
    ];
  }

  /// Perbarui tombol notifikasi tanpa menunggu event pemutaran (dipanggil saat like/acak berubah).
  void refreshControls() {
    playbackState.add(playbackState.value.copyWith(controls: _controls()));
  }

  /// Aksi custom dari notifikasi (acak & suka).
  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'sx_shuffle':
        toggleShuffle();
        break;
      case 'sx_like':
        onLikeRequested?.call();
        refreshControls();
        break;
    }
  }

  MediaItem _toItem(Track t) => MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        artUri: t.coverUrl.isNotEmpty ? Uri.tryParse(t.coverUrl) : null,
        duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
      );

  // ───────────────────────── Antrian ─────────────────────────

  Future<void> setQueue(List<Track> tracks, int startIndex) async {
    if (tracks.isEmpty) return;
    _queue = List.of(tracks);
    _rebuildOrder(startIndex.clamp(0, tracks.length - 1).toInt());
    queue.add(_queue.map(_toItem).toList());
    _failStreak = 0;
    await _playPos(_pos);
  }

  void _rebuildOrder(int startIndex) {
    if (_shuffle) {
      final rest = List<int>.generate(_queue.length, (i) => i)..remove(startIndex);
      rest.shuffle(Random());
      _order = [startIndex, ...rest];
      _pos = 0;
    } else {
      _order = List<int>.generate(_queue.length, (i) => i);
      _pos = startIndex;
    }
  }

  Future<void> playQueueIndex(int queueIndex) async {
    final p = _order.indexOf(queueIndex);
    if (p >= 0) await _playPos(p);
  }

  Future<Track> _fresh(Track t) async {
    final f = await _api.refresh(t);
    if (f == null || !f.hasStream) throw StateError('stream kosong');
    return f;
  }

  Future<void> _playPos(int p) async {
    if (p < 0 || p >= _order.length) return;
    _pos = p;
    final t = _queue[_order[p]];
    final token = ++_token; // lagu lama yang masih loading otomatis dibatalkan
    current.value = t;
    mediaItem.add(_toItem(t));

    Future<void> start(Track src) async {
      // Utamakan file offline jika tersedia dan masih ada di disk
      final local = store.offlinePath(src.id);
      if (local != null && local.isNotEmpty) {
        try {
          final f = File(local);
          if (await f.exists()) {
            await _player.setFilePath(local);
            if (token != _token) return;
            await _applyStyle();
            unawaited(_player.play());
            _failStreak = 0;
            onTrackStarted?.call(t);
            return;
          }
        } catch (_) {}
      }
      final url = await _api.proxiedStream(src);
      if (url.isEmpty) throw StateError('stream kosong');
      if (src.streamType == 'hls') {
        await _player.setAudioSource(HlsAudioSource(Uri.parse(url)));
      } else {
        await _player.setUrl(url);
      }
      if (token != _token) return;
      await _applyStyle();
      unawaited(_player.play());
      _failStreak = 0;
      onTrackStarted?.call(t);
    }

    try {
      await start(t.hasStream ? t : await _fresh(t));
    } catch (_) {
      if (token != _token) return;
      try {
        // data stream lama bisa kedaluwarsa -> ambil yang baru
        final fresh = await _fresh(t);
        if (token != _token) return;
        await start(fresh);
      } catch (_) {
        if (token != _token) return;
        _failStreak++;
        errorMessage.value = 'Gagal memutar "${t.title}"';
        if (_failStreak < 3 && _pos + 1 < _order.length) {
          await _playPos(_pos + 1);
        } else {
          await _player.stop();
        }
      }
    }
  }

  void _onCompleted() {
    if (_repeat == SxRepeatMode.one) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    if (_pos + 1 < _order.length) {
      _playPos(_pos + 1);
    } else if (_repeat == SxRepeatMode.all && _queue.isNotEmpty) {
      _rebuildOrder(_shuffle ? _order.first : 0);
      _playPos(0);
    } else {
      _player.pause();
      _player.seek(Duration.zero);
    }
  }

  // ───────────────────────── Kontrol ─────────────────────────

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_order.isEmpty) return;
    if (_pos + 1 < _order.length) {
      await _playPos(_pos + 1);
    } else if (_repeat == SxRepeatMode.all) {
      _rebuildOrder(_shuffle ? _order.first : 0);
      await _playPos(0);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_order.isEmpty) return;
    if (_player.position > const Duration(seconds: 3) || _pos == 0) {
      await _player.seek(Duration.zero);
    } else {
      await _playPos(_pos - 1);
    }
  }

  @override
  Future<void> stop() async {
    _token++;
    await _player.stop();
    current.value = null;
    mediaItem.add(null);
    await super.stop();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    shuffleOn.value = _shuffle;
    if (_queue.isNotEmpty) _rebuildOrder(currentIndex);
  }

  void cycleRepeat() {
    _repeat = SxRepeatMode.values[(_repeat.index + 1) % SxRepeatMode.values.length];
    repeatMode.value = _repeat;
  }

  // ───────────────────────── Gaya suara ─────────────────────────

  // ───────────── Tempo, volume & timer tidur ─────────────
  Future<void> setTempo(double v) async {
    tempo.value = double.parse(v.clamp(0.5, 2.0).toDouble().toStringAsFixed(2));
    await _applyStyle();
  }

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0).toDouble());

  /// null = matikan timer. Saat waktu habis, pemutaran dijeda.
  void setSleepTimer(Duration? d) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    if (d == null) {
      sleepUntil.value = null;
      return;
    }
    sleepUntil.value = DateTime.now().add(d);
    _sleepTimer = Timer(d, () {
      _sleepTimer = null;
      sleepUntil.value = null;
      _player.pause();
    });
  }

  Future<void> setStyle(String s) async {
    style.value = s;
    await _applyStyle();
  }

  Future<void> _applyStyle() async {
    double speed = 1.0;
    double pitch = 1.0;
    bool bass = false;
    switch (style.value) {
      case 'spedup':
        speed = 1.25;
        pitch = 1.12;
        break;
      case 'slowed':
        speed = 0.85;
        pitch = 0.92;
        break;
      case 'nightcore':
        speed = 1.4; // sama dengan web (1.4x)
        pitch = 1.4;
        break;
      case 'bass':
        bass = true;
        break;
    }
    try {
      await _player.setSpeed(speed * tempo.value);
    } catch (_) {}
    try {
      await _player.setPitch(pitch); // tidak didukung di sebagian platform -> diabaikan
    } catch (_) {}
    await _applyBass(bass);
  }

  Future<void> _applyBass(bool on) async {
    final eq = _eq;
    if (eq == null) return;
    try {
      await eq.setEnabled(on);
      if (!on) return;
      final p = await eq.parameters;
      final bands = p.bands;
      for (var i = 0; i < bands.length; i++) {
        final k = i == 0 ? 0.85 : (i == 1 ? 0.6 : (i == 2 ? 0.25 : 0.0));
        await bands[i].setGain(p.maxDecibels * k);
      }
    } catch (_) {}
  }
}
