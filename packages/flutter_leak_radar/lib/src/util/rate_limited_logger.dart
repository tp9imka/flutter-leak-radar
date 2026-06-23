// lib/src/util/rate_limited_logger.dart
import 'dart:developer' as developer;

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
  }) {
    if (this.level == LeakLogLevel.none) return;
    if (level.index > this.level.index) return;
    final DateTime at = now ?? DateTime.now();
    final DateTime? last = _lastLogged[message];
    if (last != null && at.difference(last) < window) return;
    _lastLogged[message] = at;
    developer.log(message, name: 'flutter_leak_radar');
  }
}
