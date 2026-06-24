# Phase B4 — Settings Screen · Implementation Report

## Status

All steps complete. `flutter analyze` clean. 192 tests pass (170 pre-existing + 22 new).

---

## Files changed

### Modified

| File | What changed |
|------|-------------|
| `lib/src/config/leak_radar_config.dart` | Added `reportThreshold: LeakSeverity` (default `info`) and `preciseTracking: bool` (default `true`). Updated `copyWith`, `==`, `hashCode`. Added `import '../model/leak_kind.dart'`. |
| `lib/src/engine/leak_engine.dart` | Added `LeakRadarConfig _config` field, `config` optional constructor param, `updateConfig(LeakRadarConfig)` method, `_startAutoScan()` helper (extracted from `start()`). `track()` and `markDisposed()` now guard on `_config.preciseTracking`. `AutoScan _autoScan` changed from `final` to mutable. |
| `lib/src/leak_radar.dart` | Added `_configNotifier: ValueNotifier<LeakRadarConfig>`, `configListenable` getter, `updateConfig()` static method. `init()` syncs notifier after engine start. `dispose()` resets notifier to `enabled: false`. `overlay()` reads `showOverlay` from notifier. Removed redundant `package:meta/meta.dart` import (covered by `flutter/foundation.dart`). |
| `lib/src/ui/leak_radar_screen.dart` | Gear icon now pushes `SettingsScreen` instead of a stub Scaffold. Added import for `settings_screen.dart`. |
| `lib/flutter_leak_radar.dart` | Added `export 'src/ui/settings_screen.dart' show SettingsScreen`. |

### Created

| File | Description |
|------|-------------|
| `lib/src/ui/settings_screen.dart` | `SettingsScreen` StatelessWidget with four sections (Overlay, Report Threshold, Auto-Scan, Precision). Listens to `LeakRadar.configListenable` via `ValueListenableBuilder`. All changes call `LeakRadar.updateConfig`. Custom `_Toggle` widget (44×26, animated, no deprecated `Switch` API). Custom segment control for threshold. `_RadioDot` instead of `Radio` to avoid Flutter 3.32 deprecation warnings. |
| `test/ui/settings_screen_test.dart` | 8 widget tests covering smoke build, overlay toggle, threshold segments, auto-scan modes, precision toggle, RECOMMENDED tag. |
| `test/engine/runtime_config_test.dart` | 10 unit tests covering `LeakEngine.updateConfig` (autoScan reconfigure, preciseTracking guard, rapid updates), `LeakRadar.configListenable` lifecycle, and new `LeakRadarConfig` field contracts (defaults, copyWith, equality, hashCode). |

---

## Architecture decisions

**Facade-held notifier** (`LeakRadar._configNotifier`) rather than delegating to the engine. The engine already has short lifetime relative to the static facade; this avoids the engine needing to expose its own `ValueNotifier` and the overlay/settings screen can subscribe once without worrying about engine restarts.

**`_startAutoScan()` extraction** in `LeakEngine` removes duplication between `start()` and `updateConfig()`. Both paths share the same scheduler/observer creation logic.

**`_RadioDot` instead of `Radio`** avoids the `groupValue`/`onChanged` deprecation introduced in Flutter 3.32.

**Periodic timer in tests** — the "Periodic · 30 s" widget test explicitly calls `LeakRadar.dispose()` before the test returns so the fake-async timer is cancelled before the framework checks for pending timers.

---

## Constraints met

- `flutter analyze` — zero issues
- All 170 pre-existing tests pass unchanged
- No `!` null assertions introduced
- No throwing into host — all engine mutations inside `runSafely`
- `LeakEngine` constructor backward-compatible (existing tests call it without `config:`)
- No `print` statements
- Lines ≤ 80 characters
