# flutter_leak_radar example

Run in profile (recommended) or debug:

```bash
cd example
flutter create .   # scaffold platform folders (not committed)
flutter run --profile
```

Repro: tap **Open leaky screen** a few times (push + back each time), then **Open Leak Radar** → **Scan now**. `_LeakyScreenState` should appear as a growth/maxLive finding (the screen never disposes its `Timer`/`StreamController`), and as a precise `notGced` finding via `LeakRadar.track`.
