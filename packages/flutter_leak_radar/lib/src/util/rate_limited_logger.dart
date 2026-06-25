// lib/src/util/rate_limited_logger.dart
import 'package:flutter/foundation.dart';

/// Verbosity for [RateLimitedLogger].
enum LeakLogLevel { none, error, warning, verbose }

/// Dedupes identical messages and caps frequency so a recurring failure can
/// never spam the console or slow the host.
class RateLimitedLogger {
  RateLimitedLogger({
    this.level = LeakLogLevel.warning,
    this.window = const Duration(seconds: 5),
  });

  final LeakLogLevel level;
  final Duration window;
  final Map<String, DateTime> _lastLogged = <String, DateTime>{};

  void log(
    String message, {
    LeakLogLevel level = LeakLogLevel.warning,
    DateTime? now,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (this.level == LeakLogLevel.none) return;
    if (level.index > this.level.index) return;
    final DateTime at = now ?? DateTime.now();
    final DateTime? last = _lastLogged[message];
    if (last != null && !at.isBefore(last) && at.difference(last) < window) {
      return;
    }
    _lastLogged[message] = at;
    // debugPrint (not developer.log) so diagnostics appear in `adb logcat` and
    // the run console where developers look — developer.log only reaches the
    // VM-service log stream (DevTools / the `flutter run` terminal).
    final String suffix = error != null ? ': $error' : '';
    debugPrint('[flutter_leak_radar] $message$suffix');
    if (stackTrace != null) debugPrint('$stackTrace');
  }
}
