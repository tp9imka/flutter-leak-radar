# radar example

Minimal wiring for the `radar` umbrella package — one import, one init call,
unified overlay and inspector for both leak and perf domains.

## Setup in `main()`

```dart
import 'package:flutter/material.dart';
import 'package:radar/radar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Radar.init(RadarConfig.standard());
  runApp(
    Radar.overlay(child: const MyApp()),
  );
}
```

`RadarConfig.standard()` enables both the memory leak detector and the
performance tracer in debug/profile builds. The overlay badge reflects the
worst signal across both: green (clean), amber (jank or errors), red
(critical leaks). Tap the badge to open `RadarScreen`.

## Wire the navigator observer

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [Radar.navigatorObserver],
      home: const HomeScreen(),
    );
  }
}
```

## Track object lifetimes

```dart
class FeatureController {
  FeatureController() {
    Radar.track(this, tag: 'FeatureController');
  }

  void dispose() {
    Radar.markDisposed(this);
  }
}
```

## Instrument operations

```dart
// Sync span.
final result = Radar.trace('parse_config', () => parseConfig(raw));

// Async span.
final data = await Radar.traceAsync('load_feed', () => api.getFeed());

// Manual start/stop.
final handle = Radar.start('encode_image');
encoder.run(bytes, onFinished: () => handle.stop());
```

## Open the unified inspector

```dart
Navigator.of(context).push(
  MaterialPageRoute(builder: (_) => const RadarScreen()),
);
```

`RadarScreen` shows a **Leaks** tab and a **Performance** tab.

## Custom configuration

```dart
await Radar.init(RadarConfig(
  leak: LeakRadarConfig.standard(
    autoScan: AutoScan(onNavigation: true, period: Duration(minutes: 2)),
    showOverlay: true,
  ),
  perf: PerfRadarConfig(
    enabled: kDebugMode || kProfileMode,
    showOverlay: true,
    jankThresholdMicros: 8333,     // 120 fps threshold
    stallThresholdMicros: 100000,
  ),
));
```
