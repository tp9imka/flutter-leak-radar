import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

import 'leaky_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LeakRadar.init(LeakRadarConfig.standard(
    rules: const [LeakRule.maxLive('_LeakyScreenState', 1)],
    suspects: SuspectSet.defaults(),
  ));
  runApp(const _App());
}

class _App extends StatelessWidget {
  const _App();
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leak Radar Example',
        home: const _Home(),
      );
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leak Radar Example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakyScreen())),
                child: const Text('Open leaky screen'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakRadarScreen())),
                child: const Text('Open Leak Radar'),
              ),
            ],
          ),
        ),
      );
}
