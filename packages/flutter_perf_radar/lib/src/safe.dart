import 'dart:developer' as dev;

/// Runs [body], swallowing any error and returning [fallback]. Never throws.
T runSafely<T>(T Function() body, {required T fallback}) {
  try {
    return body();
  } catch (e, st) {
    dev.log(
      'perf_radar suppressed error: $e',
      name: 'flutter_perf_radar',
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
}) async {
  try {
    return await body();
  } catch (e, st) {
    dev.log(
      'perf_radar suppressed async error: $e',
      name: 'flutter_perf_radar',
      error: e,
      stackTrace: st,
    );
    return fallback;
  }
}
