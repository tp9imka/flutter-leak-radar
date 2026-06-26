# flutter_leak_radar example

A full demo app lives at the repository root (`example/`) — it exercises every
lint rule and the runtime detector. This file shows the minimal wiring.

## Install

```yaml
# pubspec.yaml
dependencies:
  flutter_leak_radar: ^0.1.1
```

## Wire it up

`LeakRadar` is a no-op in release builds, so this is safe to leave in:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

void main() {
  // Enables in debug/profile, no-op in release.
  LeakRadar.init(LeakRadarConfig.standard());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // Scan for leaks after each route is popped.
      navigatorObservers: [LeakRadar.navigatorObserver],
      // Floating, draggable severity badge over the app.
      builder: (context, child) => LeakRadar.overlay(child: child!),
      home: const HomeScreen(),
    );
  }
}
```

## Inspect findings

Open the built-in dashboard (live VM-connection state, per-class growth,
retaining paths, force-GC, export):

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const LeakRadarScreen()),
);
```

## Track your own objects (optional)

For precise (non-heuristic) detection, tell the radar about an object's
lifetime:

```dart
final controller = SomeController();
LeakRadar.track(controller);
// ...later, when you dispose it:
LeakRadar.markDisposed(controller);
```

Anything tracked but never marked disposed (and not collected) is reported.
