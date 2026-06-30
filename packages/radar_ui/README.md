# radar_ui

[![pub.dev](https://img.shields.io/pub/v/radar_ui.svg)](https://pub.dev/packages/radar_ui)

The shared **design system** for the [Radar](https://pub.dev/packages/radarscope)
on-device observability suite for Flutter. It's the foundation the Radar
dashboards are built on — you normally depend on a Radar package
(`radarscope`, `flutter_leak_radar`, `flutter_perf_radar`) rather than this one
directly.

## What's inside

- **Tokens** — `RadarColors` (the dark palette), `RadarSeverity` with a
  severity→color mapping, `RadarTypography` (Space Grotesk / Hanken Grotesk /
  JetBrains Mono, with tabular figures), and `RadarDensity` spacing/radii.
- **Theme** — `radarDarkTheme()`, a dark `ThemeData` wired to the tokens.
- **Widgets** — dense, dashboard-oriented primitives: `RadarTag`,
  `RadarSparkline`, `RadarMetricTile`, `RadarSearchField`, `RadarSortHeader`,
  `RadarFilterChip`, and `RadarLivePulseDot` (reduced-motion aware).

```dart
import 'package:radar_ui/radar_ui.dart';

MaterialApp(
  theme: radarDarkTheme(),
  home: const RadarTag(label: 'CRITICAL', color: RadarColors.critical),
);
```

## License

MIT — see [LICENSE](LICENSE).
