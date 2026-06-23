# flutter-leak-radar

On-device memory leak detector for Flutter. Detects per-class heap growth and
precise object retention (unreleased `State`, `Bloc`, `Controller`, etc.) while
your app runs in debug or profile mode. Complete no-op in release — no overhead,
no code stripping required.

## Packages

| Package | Description |
|---|---|
| [`flutter_leak_radar`](packages/flutter_leak_radar/) | Runtime detector — heap sampling, precise object tracking, overlay badge, results screen, report export |
| [`flutter_leak_radar_lint`](packages/flutter_leak_radar_lint/) | Static analysis — 7 `custom_lint` rules that catch undisposed controllers, uncancelled subscriptions, and similar patterns at edit time |

## Quick start

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LeakRadar.init(LeakRadarConfig.standard(
    autoScan: AutoScan(onNavigation: true),
  ));
  runApp(const MyApp());
}

// app.dart
MaterialApp(
  navigatorObservers: [LeakRadar.navigatorObserver],
  home: LeakRadar.overlay(child: const HomeScreen()),
)
```

Tap the floating badge to open `LeakRadarScreen`. Long-press to trigger a manual
scan.

## Documentation

See [`docs/`](docs/) for architecture notes, tuning guides, and platform
compatibility details.

## License

MIT — see [LICENSE](LICENSE).
