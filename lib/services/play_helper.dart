import '../globals.dart';
import '../models/track.dart';

/// Memutar [t] dengan antrian [queue] dari layar mana pun (tanpa harus lewat MainShell).
void playFromList(Track t, List<Track> queue) {
  final playable = queue.where((e) => e.kind == ItemKind.track).toList();
  final list = playable.isEmpty ? [t] : playable;
  final idx = list.indexWhere((e) => e.id == t.id);
  audioHandler.setQueue(list, idx < 0 ? 0 : idx).catchError((Object e) {
    audioHandler.errorMessage.value = 'Gagal memutar lagu';
  });
}
