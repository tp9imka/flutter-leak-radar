// lib/src/util/safe.dart
import 'rate_limited_logger.dart';

/// Runs [body], swallowing any error and returning [fallback]. Never throws.
T runSafely<T>(
  T Function() body, {
  required T fallback,
  RateLimitedLogger? logger,
}) {
  try {
    return body();
  } catch (e, st) {
    logger?.log(
      'leak_radar suppressed error: $e',
      level: LeakLogLevel.error,
      error: e,
      stackTrace: st,
    );
    return fallback;
  }
}

/// Async variant of [runSafely].
Future<T> runSafelyAsync<T>(
  Future<T> Function() body, {
  required T fallback,
  RateLimitedLogger? logger,
}) async {
  try {
    return await body();
  } catch (e, st) {
    logger?.log(
      'leak_radar suppressed async error: $e',
      level: LeakLogLevel.error,
      error: e,
      stackTrace: st,
    );
    return fallback;
  }
}
