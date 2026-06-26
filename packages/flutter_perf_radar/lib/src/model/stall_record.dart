// Copyright (c) 2025, tp9imka. All rights reserved.

import 'package:meta/meta.dart';

/// An immutable record of one detected main-thread stall.
@immutable
final class StallRecord {
  const StallRecord({required this.durationMicros, required this.clockMicros});

  /// How long the main thread was blocked, in microseconds.
  final int durationMicros;

  /// Monotonic clock time (from [traceClockNowMicros]) when the stall was
  /// detected.
  final int clockMicros;
}
