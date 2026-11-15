import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../core/perf.dart';
import '../island/island_consts.dart';
import '../models/track.dart';
import 'audio_handler.dart';
import 'library_store.dart';

/// Dynamic Island lintas platform.
///  - Android: overlay melayang di atas aplikasi lain (flutter_overlay_window).
///  - iOS: Live Activity di Dynamic Island / Lock Screen (lewat MethodChannel + App Intents).
///
/// Perintah kontrol (toggle / next / prev) datang dari dua tempat:
///  - Android: pesan dari overlay.
///  - iOS: tombol Live Activity -> App Intent -> App Group -> notifikasi Darwin -> native kirim 'command' ke sini.
class IslandService with WidgetsBindingObserver {
  IslandService(this.handler, this.store);

  final SoundXsAudioHandler handler;
  final LibraryStore store;

  static const _iosChannel = MethodChannel('soundxs/live_activity');

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;
  bool get _isIos => !kIsWeb && Platform.isIOS;
  bool get supported => _isAndroid || _isIos;

  bool _background = false;
  bool _overlayOn = false;
  bool _busy = false;
  bool _pending = false; // ada permintaan sync saat sedang sibuk -> jalankan lagi setelahnya
  String? _lastTrackId;
  Timer? _debounce;

  void init() {
    if (!supported) return;
    WidgetsBinding.instance.addObserver(this);
    handler.current.addListener(_onTrackChanged);
    handler.player.playingStream.distinct().listen((_) => _push());
    store.addListener(_onSettings);
    if (_isAndroid) {
      FlutterOverlayWindow.overlayListener.listen(_onOverlayMessage);
    }
    if (_isIos) {
      _iosChannel.setMethodCallHandler(_onIosCall);
    }
  }

  // ───────────── Izin (Android) ─────────────
  Future<bool> hasPermission() async {
    if (!_isAndroid) return true;
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestPermission() async {
    if (!_isAndroid) return true;
    try {
      final r = await FlutterOverlayWindow.requestPermission();
      return r ?? await hasPermission();
    } catch (_) {
      return false;
    }
  }

  // ───────────── Lifecycle ─────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bg = state == AppLifecycleState.paused || state.name == 'hidden';
    final fg = state == AppLifecycleState.resumed;
    if (!bg && !fg) return; // inactive = transisi singkat, abaikan
    _background = bg;
    _sync();
  }

  void _onSettings() => _sync(force: true);

  void _onTrackChanged() {
    final t = handler.current.value;
    final changed = t?.id != _lastTrackId;
    _lastTrackId = t?.id;
    _sync();
    if (changed) _push(pop: store.islandPop);
  }

  // ───────────── Sinkronisasi tampil/sembunyi ─────────────
  void _sync({bool force = false}) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () => _doSync(force));
  }

  Future<void> _doSync(bool force) async {
    // Versi lama membuang permintaan saat sedang sibuk -> overlay bisa tidak muncul. Sekarang diantrikan.
    if (_busy) {
      _pending = true;
      return;
    }
    _busy = true;
    try {
      final hasTrack = handler.current.value != null;
      if (_isAndroid) {
        final want = store.islandOn && _background && hasTrack;
        if (want && !_overlayOn) {
          if (!await hasPermission()) return;
          await FlutterOverlayWindow.showOverlay(
            height: kIslandCollapsedH + store.islandOffset,
            width: kIslandCollapsedW,
            alignment: OverlayAlignment.topCenter,
            enableDrag: false,
            overlayTitle: 'SoundXs',
            overlayContent: 'Dynamic Island aktif',
          );
          _overlayOn = true;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          _push();
        } else if (!want && _overlayOn) {
          await FlutterOverlayWindow.closeOverlay();
          _overlayOn = false;
        } else if (want && _overlayOn && force) {
          _push(); // pengaturan berubah -> kirim ulang
        }
      } else if (_isIos) {
        if (store.islandOn && hasTrack) {
          await _push();
        } else {
          await _iosChannel.invokeMethod('end');
        }
      }
    } catch (e) {
      debugPrint('IslandService sync error: $e');
    } finally {
      _busy = false;
      if (_pending) {
        _pending = false;
        _sync();
      }
    }
  }

  // ───────────── Kirim state ke overlay / Live Activity ─────────────
  Future<void> _push({bool pop = false}) async {
    final t = handler.current.value;
    if (t == null || !store.islandOn) return;
    try {
      if (_isAndroid && _overlayOn) {
        await FlutterOverlayWindow.shareData(_payload(t, pop));
      } else if (_isIos) {
        await _pushIos(t);
      }
    } catch (e) {
      debugPrint('IslandService push error: $e');
    }
  }

  Map<String, dynamic> _payload(Track t, bool pop) => {
        't': 'state',
        'title': t.title,
        'artist': t.artist,
        'cover': t.coverUrl,
        'playing': handler.player.playing,
        'pos': handler.player.position.inMilliseconds,
        'dur': handler.player.duration?.inMilliseconds ?? t.durationMs,
        'style': store.islandStyle,
        'offset': store.islandOffset,
        'pop': pop,
        'lite': Perf.instance.lite.value,
      };

  Future<void> _pushIos(Track t) async {
    String? art;
    if (t.coverUrl.isNotEmpty) {
      try {
        final f = await DefaultCacheManager().getSingleFile(t.coverUrl);
        art = f.path;
      } catch (_) {}
    }
    await _iosChannel.invokeMethod('update', {
      'title': t.title,
      'artist': t.artist,
      'playing': handler.player.playing,
      'positionMs': handler.player.position.inMilliseconds,
      'durationMs': handler.player.duration?.inMilliseconds ?? t.durationMs,
      'artworkPath': art ?? '',
    });
  }

  // ───────────── Perintah kontrol (dari overlay Android & tombol iOS) ─────────────
  void _command(String? c) {
    try {
      switch (c) {
        case 'toggle':
          if (handler.player.playing) {
            handler.pause();
          } else {
            handler.play();
          }
          break;
        case 'next':
          handler.skipToNext();
          break;
        case 'prev':
          handler.skipToPrevious();
          break;
        case 'sync':
          break;
      }
    } catch (e) {
      debugPrint('IslandService command error ($c): $e');
    }
    // kirim status SEBENARNYA setelah perintah (overlay tidak menebak sendiri)
    Future<void>.delayed(const Duration(milliseconds: 120), () => _push());
  }

  void _onOverlayMessage(dynamic msg) {
    if (msg is! Map || msg['t'] != 'cmd') return;
    _command(msg['c']?.toString());
  }

  Future<void> _onIosCall(MethodCall call) async {
    if (call.method != 'command') return;
    final args = call.arguments;
    final c = args is Map ? args['c']?.toString() : null;
    _command(c);
  }
}
