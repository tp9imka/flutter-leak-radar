// Copyright (c) 2025, tp9imka. All rights reserved.

import 'dart:async';

import 'package:radar_trace/radar_trace.dart';

/// Detects main-thread stalls by measuring how late each timer tick arrives.
///
/// If a tick is delayed by more than [threshold], the delay is reported via
/// [onStall]. This works because `Timer.periodic` callbacks run on the main
/// isolate — a blocked main thread delays the tick.
final class StallWatchdog {
  StallWatchdog({
    required Duration interval,
    required Duration threshold,
    required void Function(int durationMicros) onStall,
    int Function()? clockMicros,
  }) : _threshold = threshold,
       _onStall = onStall,
       _clockMicros = clockMicros ?? traceClockNowMicros {
    _intervalMicros = interval.inMicroseconds;
    _lastTickMicros = _clockMicros();
    _timer = Timer.periodic(interval, _tick);
  }

  final Duration _threshold;
  final void Function(int durationMicros) _onStall;
  final int Function() _clockMicros;

  late final int _intervalMicros;
  late int _lastTickMicros;
  late final Timer _timer;

  void _tick(Timer _) {
    final now = _clockMicros();
    final elapsed = now - _lastTickMicros;
    _lastTickMicros = now;
    final late = elapsed - _intervalMicros;
    if (late > _threshold.inMicroseconds) {
      _onStall(late);
    }
  }

  /// Stops the watchdog timer. Safe to call multiple times.
  void dispose() {
    _timer.cancel();
  }
}
