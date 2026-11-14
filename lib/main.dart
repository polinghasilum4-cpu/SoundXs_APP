import 'dart:io' show Platform;
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app.dart';
import 'core/perf.dart';
import 'globals.dart';
import 'island/island_overlay.dart';
import 'services/audio_handler.dart';
import 'services/island_service.dart';

/// Entry point jendela overlay Android (Dynamic Island). Nama HARUS `overlayMain`
/// dan HARUS ada di main.dart.
@pragma('vm:entry-point')
void overlayMain() => runIslandOverlay();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await store.load();
  await downloads.load();
  Perf.instance.start(PerfMode.values[store.perfMode]);

  // Hanya SATU inisialisasi: AudioService. (Versi lama memanggil JustAudioBackground.init
  // DAN AudioService.init sekaligus -> crash "AudioService already initialized".)
  audioHandler = await AudioService.init(
    builder: () => SoundXsAudioHandler.create(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.soundxs.app.channel.audio',
      androidNotificationChannelName: 'SoundXs Playback',
      androidNotificationOngoing: true,
    ),
  );
  audioHandler
    ..onTrackStarted = store.recordPlay
    ..localAudio = downloads.localAudio
    ..localCover = downloads.localCover
    ..isLiked = ((t) => store.isLiked(t.id))
    ..toggleLike = store.toggleLike;
  // Tombol like di notifikasi / Island ikut berubah saat daftar disukai berubah.
  store.addListener(audioHandler.refreshState);

  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  } catch (_) {}

  island = IslandService(audioHandler, store)..init();

  runApp(const SoundXsApp());

  // Izin notifikasi diminta SETELAH UI tampil (tidak menahan startup).
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (_) {}
  });
}
