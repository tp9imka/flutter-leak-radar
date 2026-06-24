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
      period: Duration(seconds: 20),
    ),
    rules: const [
      // Flag _LeakyScreenState if more than 1 instance is live at once.
      LeakRule.maxLive('_LeakyScreenState', 1),
      // Flag LeakyCubit on any growth (it should be gone after pop).
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
