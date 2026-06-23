# flutter_leak_radar example

The macOS runner is committed — no `flutter create` prerequisite needed.

Run in profile mode (recommended) or debug:

```bash
cd example && flutter run -d macos --profile
```

Repro: tap **Open leaky screen** a few times (push + back each time), then **Open Leak Radar** → **Scan now**. `_LeakyScreenState` should appear as a growth/maxLive finding (the screen never disposes its `Timer`/`StreamController`), and as a precise `notGced` finding via `LeakRadar.track`.
