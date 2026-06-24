// example/lib/main.dart
//
// Leak Radar demo app — full testbed for:
//   • Runtime detector (heap-based, navigation-triggered + periodic scans)
//   • Lint plugin (7 custom_lint rules exercised across leaky_screen.dart and
//     leaky_cubit.dart)
//
// Run the app:   flutter run
// Run lints:     dart run custom_lint   (from the example/ directory)
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

import 'leaky_bloc_screen.dart';
import 'leaky_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LeakRadar.init(LeakRadarConfig.standard(
    autoScan: const AutoScan(
      onNavigation: true,
      period: Duration(seconds: 8),
    ),
    // Surface precise (track + markDisposed) leaks quickly in the demo:
    // 1 GC cycle + 1s grace, instead of the 3-cycle / 2s production defaults.
    // This is why popping a leaky screen once flags it within a scan or two.
    gcCyclesForPreciseLeak: 1,
    disposalGrace: const Duration(seconds: 1),
    rules: const [
      // Heap-growth rules. These need REPEATED visits to trip: maxLive fires
      // only when >1 _LeakyScreenState is live at once, and growth needs
      // LeakyCubit's instance count to climb across >=2 scans.
      LeakRule.maxLive('_LeakyScreenState', 1),
      LeakRule.growth('LeakyCubit'),
    ],
  ));
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return LeakRadar.overlay(
      child: MaterialApp(
        title: 'Leak Radar Demo',
        navigatorObservers: [LeakRadar.navigatorObserver],
        home: const _HomeScreen(),
      ),
    );
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leak Radar Demo')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Push a leaky screen, pop back, then wait for the\n'
              'navigation scan (or open the dashboard manually).',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LeakyScreen(),
                ),
              ),
              child: const Text('Open Leaky Screen\n(patterns 1–6)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LeakyBlocScreen(),
                ),
              ),
              child: const Text('Open Leaky Bloc Screen\n(pattern 7)'),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LeakRadarScreen(),
                ),
              ),
              child: const Text('Open Leak Radar Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}
