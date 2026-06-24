// lib/src/triggers/scan_scheduler.dart
import 'dart:async';

/// Fires [onTick] at [period] intervals. No-op when [period] is null.
/// Designed for use by [LeakEngine] only.
class ScanScheduler {
  ScanScheduler({
    required Duration? period,
    required Future<void> Function() onTick,
  }) : _period = period,
       _onTick = onTick;

  final Duration? _period;
  final Future<void> Function() _onTick;
  Timer? _timer;

  /// Starts the periodic timer. Idempotent — a second call is a no-op.
  void start() {
    if (_period == null || _timer != null) return;
    _timer = Timer.periodic(_period, (_) => _onTick());
  }

  /// Cancels the timer. Safe to call multiple times.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
