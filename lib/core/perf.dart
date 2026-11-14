import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum PerfMode { auto, saver, full }

/// Pengatur kualitas visual adaptif.
/// `lite == true` -> blur, bayangan & animasi berat dimatikan.
/// Mode auto memantau frame time; kalau device sering nge-lag, otomatis hemat.
class Perf {
  Perf._();
  static final Perf instance = Perf._();

  final ValueNotifier<bool> lite = ValueNotifier<bool>(false);
  PerfMode _mode = PerfMode.auto;
  PerfMode get mode => _mode;

  int _frames = 0;
  int _slow = 0;
  int _badWindows = 0;
  bool _started = false;

  void start(PerfMode m) {
    _mode = m;
    _apply();
    if (_started) return;
    _started = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void setMode(PerfMode m) {
    _mode = m;
    _frames = 0;
    _slow = 0;
    _badWindows = 0;
    _apply();
  }

  void _apply() {
    switch (_mode) {
      case PerfMode.saver:
        lite.value = true;
        break;
      case PerfMode.full:
      case PerfMode.auto:
        lite.value = false;
        break;
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_mode != PerfMode.auto || lite.value) return;
    for (final f in timings) {
      _frames++;
      if (f.totalSpan.inMicroseconds > 24000) _slow++;
    }
    if (_frames >= 120) {
      final ratio = _slow / _frames;
      if (ratio > 0.30) {
        _badWindows++;
        if (_badWindows >= 2) lite.value = true;
      } else {
        _badWindows = 0;
      }
      _frames = 0;
      _slow = 0;
    }
  }
}
