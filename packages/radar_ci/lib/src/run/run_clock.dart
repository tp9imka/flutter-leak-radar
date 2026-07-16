/// Wall-clock and delay seam for the sampling loop, so tests can drive the
/// full cadence in virtual time instead of waiting minutes of real time.
abstract interface class RunClock {
  /// Host wall-clock microseconds since epoch.
  int nowMicros();

  /// Waits for [duration]; a non-positive duration returns immediately.
  Future<void> delay(Duration duration);
}

/// The production clock: real epoch time and real delays.
final class SystemRunClock implements RunClock {
  /// Creates a system clock.
  const SystemRunClock();

  @override
  int nowMicros() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<void> delay(Duration duration) => duration <= Duration.zero
      ? Future.value()
      : Future<void>.delayed(duration);
}
