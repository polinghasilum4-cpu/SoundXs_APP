import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:math';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import '../models/track.dart';
import 'api_service.dart';

enum SxRepeatMode { off, all, one }

/// Gaya suara. Tiap gaya mengatur parameter NYATA pada mesin audio:
/// tempo & pitch (ExoPlayer), kurva equalizer (AndroidEqualizer), reverb & virtualizer
/// (android.media.audiofx lewat MethodChannel di MainActivity.kt).
class SoundStyle {
  const SoundStyle(this.key, this.label, this.desc,
      {this.tempo = 1.0, this.semitones = 0, this.eq = const [0, 0, 0, 0, 0], this.reverb = 0, this.virtualizer = 0});
  final String key;
  final String label;
  final String desc;
  final double tempo;
  final int semitones;

  /// Kurva EQ 5 titik (rendah -> tinggi) sebagai pecahan dari rentang dB perangkat (-1..1).
  final List<double> eq;

  /// Preset reverb Android: 0 mati, 1 small room, 2 medium room, 3 large room, 4 medium hall, 5 large hall, 6 plate.
  final int reverb;

  /// Kekuatan virtualizer 0..1000.
  final int virtualizer;
}

const kSoundStyleList = <SoundStyle>[
  SoundStyle('normal', 'Normal', 'Lagu apa adanya'),
  SoundStyle('spedup', 'Sped up', 'Lebih cepat dan tinggi (1.15x, +2 nada)', tempo: 1.15, semitones: 2),
  SoundStyle('slowed', 'Slowed + reverb', 'Lebih pelan dan rendah, dengan gema hall (0.85x, -2 nada)',
      tempo: 0.85, semitones: -2, reverb: 5),
  SoundStyle('nightcore', 'Nightcore', 'Jauh lebih cepat dan tinggi (1.4x, +6 nada)', tempo: 1.4, semitones: 6),
  SoundStyle('lofi', 'Lo-fi', 'Hangat dan santai: sedikit pelan, treble diredam, gema tipis',
      tempo: 0.95, semitones: -1, eq: [0.3, 0.2, 0, -0.4, -0.7], reverb: 1),
  SoundStyle('8d', '8D (virtual surround)', 'Suara luas mengelilingi kepala. Paling enak pakai headset',
      reverb: 2, virtualizer: 1000),
  SoundStyle('concert', 'Konser / Hall', 'Gema ruangan besar seperti aula konser', reverb: 5, eq: [0.1, 0, 0, 0.1, 0.15]),
  SoundStyle('bass', 'Bass Boost', 'Bass lebih tebal', eq: [0.85, 0.6, 0.25, 0, 0]),
];

SoundStyle styleByKey(String k) => kSoundStyleList.firstWhere((s) => s.key == k, orElse: () => kSoundStyleList.first);

// Kompatibilitas dengan kode lama.
final kSoundStyles = kSoundStyleList.map((e) => e.key).toList();
final kSoundLabels = {for (final s in kSoundStyleList) s.key: s.label};

class EqBandInfo {
  const EqBandInfo(this.freqHz, this.minDb, this.maxDb);
  final double freqHz;
  final double minDb;
  final double maxDb;
}

class SoundXsAudioHandler extends BaseAudioHandler {
  SoundXsAudioHandler._(this._player, this._eq) {
    _subs.add(_player.playbackEventStream.map(_transformEvent).listen(
          playbackState.add,
          onError: (Object e, StackTrace st) {},
        ));
    _subs.add(_player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    }));
    // Durasi asli dari stream (lebih akurat dari metadata API) -> notifikasi ikut update.
    _subs.add(_player.durationStream.listen((d) {
      final item = mediaItem.value;
      if (d != null && item != null && item.duration != d) {
        mediaItem.add(item.copyWith(duration: d));
      }
    }));
    if (_fxAvailable) {
      _subs.add(_player.androidAudioSessionIdStream.listen((id) {
        if (id != null) _attachFx(id);
      }));
    }
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
  static bool get _fxAvailable => !kIsWeb && Platform.isAndroid;
  static const _fx = MethodChannel('soundxs/fx');

  final AudioPlayer _player;
  final AndroidEqualizer? _eq;
  final ApiService _api = ApiService();
  final List<StreamSubscription<dynamic>> _subs = [];

  List<Track> _queue = [];
  List<int> _order = [];
  int _pos = 0;
  int _token = 0;
  int _failStreak = 0;
  bool _shuffle = false;
  SxRepeatMode _repeat = SxRepeatMode.off;

  // ── hook dari luar (diisi di main.dart) ──
  void Function(Track track)? onTrackStarted;
  String? Function(String id)? localAudio;
  String? Function(String id)? localCover;
  bool Function(Track t)? isLiked;
  void Function(Track t)? toggleLike;

  /// Lagu yang sedang aktif. UI cukup listen ini (otomatis ikut saat auto-next).
  final ValueNotifier<Track?> current = ValueNotifier<Track?>(null);
  final ValueNotifier<bool> shuffleOn = ValueNotifier<bool>(false);
  final ValueNotifier<SxRepeatMode> repeatMode = ValueNotifier<SxRepeatMode>(SxRepeatMode.off);
  final ValueNotifier<String> style = ValueNotifier<String>('normal');
  final ValueNotifier<double> tempo = ValueNotifier<double>(1.0);
  final ValueNotifier<int> pitchSemi = ValueNotifier<int>(0);
  final ValueNotifier<String?> errorMessage = ValueNotifier<String?>(null);
  final ValueNotifier<String?> fxNotice = ValueNotifier<String?>(null);

  // Equalizer
  final ValueNotifier<List<EqBandInfo>> eqBands = ValueNotifier<List<EqBandInfo>>(const []);
  final ValueNotifier<bool> eqEnabled = ValueNotifier<bool>(false);
  List<double> _userGains = [];
  List<double> get eqGains => List.unmodifiable(_userGains);

  // Sleep timer
  final ValueNotifier<DateTime?> sleepEnd = ValueNotifier<DateTime?>(null);
  final ValueNotifier<bool> sleepAtTrackEnd = ValueNotifier<bool>(false);
  Timer? _sleepTimer;

  AudioPlayer get player => _player;
  List<Track> get queueList => List.unmodifiable(_queue);
  int get currentIndex => _order.isEmpty ? 0 : _order[_pos];
  bool get isShuffle => _shuffle;
  bool get isPlaying => _player.playing;

  late final Stream<Duration> slowPosition = _player
      .createPositionStream(
        minPeriod: const Duration(milliseconds: 500),
        maxPeriod: const Duration(milliseconds: 500),
      )
      .asBroadcastStream();

  // ───────────────────────── State notifikasi (MediaSession) ─────────────────────────

  /// Dipanggil saat like/shuffle berubah supaya tombol di notifikasi ikut berubah.
  void refreshState() {
    try {
      playbackState.add(_transformEvent(_player.playbackEvent));
    } catch (_) {}
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    final t = current.value;
    final liked = t != null && (isLiked?.call(t) ?? false);
    return PlaybackState(
      controls: [
        MediaControl.custom(
          androidIcon: _shuffle ? 'drawable/ic_sx_shuffle_on' : 'drawable/ic_sx_shuffle_off',
          label: 'Shuffle',
          name: 'shuffle',
        ),
        MediaControl.skipToPrevious,
        _player.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.custom(
          androidIcon: liked ? 'drawable/ic_sx_heart_on' : 'drawable/ic_sx_heart_off',
          label: 'Suka',
          name: 'like',
        ),
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [1, 2, 3],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: currentIndex,
    );
  }

  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    switch (name) {
      case 'shuffle':
        toggleShuffle();
        break;
      case 'like':
        final t = current.value;
        if (t != null) toggleLike?.call(t);
        refreshState();
        break;
    }
    return null;
  }

  MediaItem _toItem(Track t) {
    final cover = localCover?.call(t.id);
    Uri? art;
    if (cover != null) {
      art = Uri.file(cover);
    } else if (t.coverUrl.isNotEmpty) {
      art = Uri.tryParse(t.coverUrl);
    }
    return MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      artUri: art,
      duration: t.durationMs > 0 ? Duration(milliseconds: t.durationMs) : null,
    );
  }

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

  @override
  Future<void> skipToQueueItem(int index) => playQueueIndex(index);

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
    refreshState(); // tombol like di notifikasi mengikuti lagu baru

    // 1) File offline (tanpa internet).
    final local = localAudio?.call(t.id);
    if (local != null && File(local).existsSync()) {
      try {
        await _player.setFilePath(local);
        if (token != _token) return;
        await _applyAll();
        unawaited(_player.play());
        _failStreak = 0;
        onTrackStarted?.call(t);
        return;
      } catch (_) {
        // file rusak -> lanjut ke streaming
      }
    }

    // 2) Streaming online (alur lama dipertahankan).
    Future<void> start(Track src) async {
      final url = await _api.proxiedStream(src);
      if (url.isEmpty) throw StateError('stream kosong');
      if (src.streamType == 'hls') {
        await _player.setAudioSource(HlsAudioSource(Uri.parse(url)));
      } else {
        await _player.setUrl(url);
      }
      if (token != _token) return;
      await _applyAll();
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
    if (sleepAtTrackEnd.value) {
      sleepAtTrackEnd.value = false;
      _player.pause();
      _player.seek(Duration.zero);
      return;
    }
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
    cancelSleep();
    await _player.stop();
    current.value = null;
    mediaItem.add(null);
    await super.stop();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    shuffleOn.value = _shuffle;
    if (_queue.isNotEmpty) _rebuildOrder(currentIndex);
    refreshState();
  }

  void cycleRepeat() {
    _repeat = SxRepeatMode.values[(_repeat.index + 1) % SxRepeatMode.values.length];
    repeatMode.value = _repeat;
  }

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0).toDouble());

  // ───────────────────────── Sleep timer ─────────────────────────

  void setSleepTimer(Duration d) {
    cancelSleep();
    sleepEnd.value = DateTime.now().add(d);
    _sleepTimer = Timer(d, _sleepFire);
  }

  void setSleepAtTrackEnd(bool on) {
    if (on) cancelSleep();
    sleepAtTrackEnd.value = on;
  }

  void cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    sleepEnd.value = null;
    sleepAtTrackEnd.value = false;
  }

  Future<void> _sleepFire() async {
    _sleepTimer = null;
    sleepEnd.value = null;
    final before = _player.volume;
    try {
      for (var i = 9; i >= 0; i--) {
        await _player.setVolume(before * i / 10);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await _player.pause();
    } finally {
      await _player.setVolume(before);
    }
  }

  // ───────────────────────── Gaya suara / tempo / pitch / EQ ─────────────────────────

  Future<void> setStyle(String key) async {
    final s = styleByKey(key);
    style.value = s.key;
    tempo.value = s.tempo;
    pitchSemi.value = s.semitones;
    await _applyAll();
  }

  Future<void> setTempo(double v) async {
    tempo.value = double.parse(v.clamp(0.5, 2.0).toStringAsFixed(2));
    await _applyTempoPitch();
  }

  Future<void> setPitchSemitones(int v) async {
    pitchSemi.value = v.clamp(-12, 12).toInt();
    await _applyTempoPitch();
  }

  Future<void> resetTempoPitch() async {
    tempo.value = 1.0;
    pitchSemi.value = 0;
    await _applyTempoPitch();
  }

  Future<void> resetAllEffects() async {
    style.value = 'normal';
    tempo.value = 1.0;
    pitchSemi.value = 0;
    _userGains = List<double>.filled(_userGains.length, 0);
    eqEnabled.value = false;
    await _applyAll();
  }

  Future<void> _applyTempoPitch() async {
    try {
      await _player.setSpeed(tempo.value);
    } catch (_) {}
    try {
      await _player.setPitch(pow(2, pitchSemi.value / 12).toDouble());
    } catch (_) {}
    refreshState();
  }

  Future<void> _applyAll() async {
    await _applyTempoPitch();
    await _loadEqBands();
    await _applyEq();
    await _applyFx();
  }

  // Equalizer ------------------------------------------------------------------------------

  Future<void> _loadEqBands() async {
    final eq = _eq;
    if (eq == null || eqBands.value.isNotEmpty) return;
    try {
      final p = await eq.parameters;
      eqBands.value = [for (final b in p.bands) EqBandInfo(b.centerFrequency, p.minDecibels, p.maxDecibels)];
      _userGains = List<double>.filled(p.bands.length, 0);
    } catch (_) {}
  }

  Future<void> setEqEnabled(bool on) async {
    eqEnabled.value = on;
    await _applyEq();
  }

  Future<void> setEqGain(int band, double db) async {
    if (band < 0 || band >= _userGains.length) return;
    _userGains[band] = db;
    await _applyEq();
  }

  Future<void> resetEq() async {
    _userGains = List<double>.filled(_userGains.length, 0);
    await _applyEq();
  }

  Future<void> _applyEq() async {
    final eq = _eq;
    if (eq == null || _userGains.isEmpty) return;
    try {
      final curve = styleByKey(style.value).eq;
      final styleActive = curve.any((v) => v != 0);
      final on = eqEnabled.value || styleActive;
      await eq.setEnabled(on);
      if (!on) return;
      final p = await eq.parameters;
      final n = p.bands.length;
      for (var i = 0; i < n; i++) {
        final ci = n <= 1 ? 0 : (i * 4 / (n - 1)).round();
        final fromStyle = curve[ci] * (curve[ci] >= 0 ? p.maxDecibels : -p.minDecibels);
        final user = eqEnabled.value ? _userGains[i] : 0.0;
        await p.bands[i].setGain((user + fromStyle).clamp(p.minDecibels, p.maxDecibels).toDouble());
      }
    } catch (_) {}
  }

  // Reverb & virtualizer (native) --------------------------------------------------------

  int? _sessionId;

  Future<void> _attachFx(int id) async {
    _sessionId = id;
    try {
      await _fx.invokeMethod<bool>('attach', {'session': id});
      await _applyFx();
    } on MissingPluginException {
      fxNotice.value = 'Reverb/8D tidak tersedia di build ini.';
    } catch (_) {}
  }

  Future<void> _applyFx() async {
    if (!_fxAvailable) return;
    final id = _sessionId ?? _player.androidAudioSessionId;
    if (id == null) return;
    final s = styleByKey(style.value);
    try {
      if (_sessionId != id) await _fx.invokeMethod<bool>('attach', {'session': id});
      _sessionId = id;
      final okR = await _fx.invokeMethod<bool>('reverb', {'preset': s.reverb}) ?? false;
      final okV = await _fx.invokeMethod<bool>('virtualizer', {'strength': s.virtualizer}) ?? false;
      final needR = s.reverb > 0;
      final needV = s.virtualizer > 0;
      if ((needR && !okR) || (needV && !okV)) {
        fxNotice.value = 'Perangkat ini tidak mendukung ${needR && !okR ? "reverb" : "virtualizer"} untuk gaya "${s.label}". '
            'Tempo, pitch, dan EQ tetap bekerja.';
      } else {
        fxNotice.value = null;
      }
    } on MissingPluginException {
      fxNotice.value = 'Reverb/8D tidak tersedia di build ini.';
    } catch (_) {}
  }

  Future<void> disposeHandler() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _sleepTimer?.cancel();
    try {
      await _fx.invokeMethod<void>('release');
    } catch (_) {}
    await _player.dispose();
  }
}
