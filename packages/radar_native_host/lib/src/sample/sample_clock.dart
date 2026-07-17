/// Wall-clock and delay seam for the overnight sampling loop, so tests drive
/// the whole cadence (hours of intervals, backoff windows) in virtual time
/// instead of waiting in real time.
///
/// Mirrors the `radar_ci` run clock: [nowMicros] stamps snapshots and marks;
/// [delay] is the only place the loop ever waits, so a fake clock that advances
/// [nowMicros] synchronously turns an 8-hour session into an instant test.
abstract interface class SampleClock {
  /// Host wall-clock microseconds since epoch.
  int nowMicros();

  /// Waits for [duration]; a non-positive duration returns immediately.
  Future<void> delay(Duration duration);
}

/// The production clock: real epoch time and real delays.
final class SystemSampleClock implements SampleClock {
  /// Creates a system clock.
  const SystemSampleClock();

  @override
  int nowMicros() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<void> delay(Duration duration) => duration <= Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(duration);
}
