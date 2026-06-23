// lib/src/triggers/navigator_observer.dart
import 'dart:async';

import 'package:flutter/widgets.dart';

/// A [NavigatorObserver] that fires a debounced scan when the user
/// navigates back via [didPop].
///
/// Instantiate once and add to [MaterialApp.navigatorObservers]:
///
/// ```dart
/// MaterialApp(
///   navigatorObservers: [
///     LeakRadarNavigatorObserver(onScan: () async => radar.scan()),
///   ],
/// )
/// ```
///
/// Call [dispose] when the observer is no longer needed to cancel any
/// pending timer and prevent stale callbacks from firing.
class LeakRadarNavigatorObserver extends NavigatorObserver {
  /// Creates a [LeakRadarNavigatorObserver].
  ///
  /// [onScan] is invoked after [debounce] has elapsed since the last
  /// [didPop] event. Errors thrown by [onScan] are caught and silenced
  /// so they never propagate into the Flutter framework.
  ///
  /// [debounce] defaults to 500 ms, which is long enough to coalesce
  /// rapid back-navigations but short enough to feel immediate.
  LeakRadarNavigatorObserver({
    required Future<void> Function() onScan,
    Duration debounce = const Duration(milliseconds: 500),
  })  : _onScan = onScan,
        _debounce = debounce;

  final Future<void> Function() _onScan;
  final Duration _debounce;
  Timer? _debounceTimer;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _scheduledScan);
  }

  /// Cancels any pending debounce timer.
  ///
  /// Call this when the observer is removed from the navigator's observer list
  /// to avoid firing scans after the navigator has been disposed.
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  void _scheduledScan() {
    _debounceTimer = null;
    // Errors from the scan callback must not surface into the Flutter
    // framework scheduler.
    _onScan().catchError((_) {});
  }
}
