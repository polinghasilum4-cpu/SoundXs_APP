import 'services/audio_handler.dart';
import 'services/island_service.dart';
import 'services/library_store.dart';

/// Diisi di main() sebelum runApp.
late SoundXsAudioHandler audioHandler;
late IslandService island;

/// Penyimpanan lokal: disukai, riwayat, hitungan putar, pengaturan.
final LibraryStore store = LibraryStore();
