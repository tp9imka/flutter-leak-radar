// lib/src/radar.dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';
import 'package:flutter_perf_radar/flutter_perf_radar.dart';
import 'package:radar_trace/radar_trace.dart';

import 'radar_config.dart';
import 'radar_overlay.dart';
import 'radar_screen.dart';

/// Unified on-device observability facade.
///
/// Initialises both [LeakRadar] and [PerfRadar] from a single [RadarConfig].
/// Every method is a no-op when disabled or in release builds and never
/// throws into the host application.
///
/// Typical setup in `main()`:
/// ```dart
/// await Radar.init(RadarConfig.standard());
/// runApp(
///   Radar.overlay(child: MyApp()),
/// );
/// ```
abstract final class Radar {
  /// Initialises both domain engines with [config].
  ///
  /// Calls [LeakRadar.init] and [PerfRadar.init] in parallel.
  /// Safe to call multiple times — disposes previous engines first.
  static Future<void> init(RadarConfig config) async {
    await Future.wait([
      LeakRadar.init(config.leak),
      PerfRadar.init(config.perf),
    ]);
  }

  /// Disposes both domain engines.
  ///
  /// Safe to call multiple times. [init] may be called again afterwards.
  static Future<void> dispose() async {
    await Future.wait([LeakRadar.dispose(), PerfRadar.dispose()]);
  }

  /// Delegates to [LeakRadar.track].
  ///
  /// Registers [object] for precise lifecycle tracking. A no-op when the
  /// leak engine is not running.
  static void track(Object object, {required String tag}) =>
      LeakRadar.track(object, tag: tag);

  /// Delegates to [LeakRadar.markDisposed].
  ///
  /// Notifies the leak engine that [object] has been intentionally disposed.
  /// A no-op when the leak engine is not running.
  static void markDisposed(Object object) => LeakRadar.markDisposed(object);

  /// Delegates to [PerfRadar.trace].
  ///
  /// Measures [body] synchronously and records a span. Returns [body]'s
  /// result. A no-op when the perf engine is not running.
  static T trace<T>(String name, T Function() body, {String? category}) =>
      PerfRadar.trace(name, body, category: category);

  /// Delegates to [PerfRadar.traceAsync].
  ///
  /// Measures [body] asynchronously and records a span. A no-op when the
  /// perf engine is not running.
  static Future<T> traceAsync<T>(
    String name,
    Future<T> Function() body, {
    String? category,
  }) => PerfRadar.traceAsync(name, body, category: category);

  /// Delegates to [PerfRadar.start] and returns a [SpanHandle].
  ///
  /// Returns an inert handle when the perf engine is not running.
  static SpanHandle start(String name, {String? category}) =>
      PerfRadar.start(name, category: category);

  /// Returns the [NavigatorObserver] from [LeakRadar].
  ///
  /// Safe to add to [MaterialApp.navigatorObservers] unconditionally.
  static NavigatorObserver get navigatorObserver => LeakRadar.navigatorObserver;

  /// Pushes [RadarScreen] as a full-screen route onto [context]'s navigator.
  ///
  /// Use this instead of constructing [RadarScreen] directly so that the
  /// close button always works: the screen falls back to
  /// `Navigator.maybeOf(context)?.pop()` when no explicit [onClose] is set.
  ///
  /// [initialTab] selects the starting tab (0 = Leaks, 1 = Perf, 2 = Stability).
  static void openInspector(BuildContext context, {int initialTab = 0}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RadarScreen(initialTab: initialTab),
      ),
    );
  }

  /// Wraps [child] in a [RadarOverlay].
  ///
  /// Returns [child] unchanged when both domain engines have
  /// [showOverlay] set to false (or were never initialised). Safe to call
  /// unconditionally — the overlay is a no-op in release when [init] was
  /// not called.
  static Widget overlay({required Widget child}) {
    final leakConfig = LeakRadar.configListenable.value;
    final perfConfig = PerfRadar.configListenable.value;
    final show = leakConfig.showOverlay || perfConfig.showOverlay;
    return RadarOverlay(show: show, child: child);
  }
}
