// example/lib/main.dart
//
// Radar suite showcase app — real live demos of every unified-radar feature:
//   • Leak tracking (precise notGced + heap-growth rules)
//   • Perf tracing (sync + async spans → Spans tab p50/p95/p99)
//   • Rebuild counting (TracedSubtree → Rebuilds panel)
//   • Frame jank (real over-budget frames → Frames tab)
//   • Stability errors (FlutterError handler → Stability tab)
//   • Stall detection (busy-wait on the main isolate → Stability tab)
//   • Lint plugin (7 custom_lint rules exercised in leaky_screen.dart)
//
// Run the app:   flutter run
// Run lints:     dart run custom_lint   (from the example/ directory)
import 'package:flutter/material.dart';
import 'package:radarscope/radarscope.dart';

import 'leak_self_test.dart';
import 'leaky_bloc_screen.dart';
import 'leaky_screen.dart';
import 'showcase/showcase_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Radar.init(
    RadarConfig(
      leak: LeakRadarConfig.standard(
        autoScan: const AutoScan(
          onNavigation: true,
          period: Duration(seconds: 8),
        ),
        // minClusterSize:1 surfaces a single-instance demo leak immediately.
        // everyNthNavigation:5 keeps graph scans infrequent.
        graphScan: const GraphScan(
          everyNthNavigation: 5,
          minClusterSize: 1,
          maxGraphObjects: 500000,
        ),
        // Surface precise (track + markDisposed) leaks quickly in the demo.
        gcCyclesForPreciseLeak: 1,
        disposalGrace: const Duration(seconds: 1),
        rules: const [
          LeakRule.maxLive('_LeakyScreenState', 1),
          LeakRule.growth('LeakyCubit'),
        ],
      ).copyWith(logLevel: LeakLogLevel.verbose),
      perf: PerfRadarConfig.standard().copyWith(
        // Lower stall threshold so the demo stall button fires quickly.
        stallThresholdMicros: 200000,
      ),
    ),
  );
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return Radar.overlay(
      child: MaterialApp(
        title: 'Radar Showcase',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2fe39b),
            brightness: Brightness.dark,
          ),
        ),
        navigatorObservers: [Radar.navigatorObserver],
        home: ShowcaseHome(
          leakyScreenBuilder: () => const LeakyScreen(),
          leakyBlocScreenBuilder: () => const LeakyBlocScreen(),
          onSelfTest: (nav) => runLeakSelfTest(nav),
        ),
      ),
    );
  }
}
