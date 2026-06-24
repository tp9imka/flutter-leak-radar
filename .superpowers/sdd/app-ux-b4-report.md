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

---

## Final-review fix pass

Three post-B4 fixes applied in commits `f622721`, `9a10472`, `9ef7f85` on `feat/app-ux`.

### Fix 1 (CRITICAL) — `reportThreshold` now filters scan output

**Problem:** `LeakRadarConfig.reportThreshold` was stored but never used; every finding reached the stream and `latest` regardless of severity.

**Changes to `lib/src/engine/leak_engine.dart`:**
- `_latest: LeakReport?` renamed to `_latestFullReport` (stores the unfiltered analyzer output).
- New `_latestFiltered: LeakReport?` stores the threshold-filtered view.
- New `_filtered(LeakReport full)` builds a `LeakReport` keeping only findings where `severity.index >= _config.reportThreshold.index`.
- `scan()` stores the full report and emits/returns the filtered one.
- `updateConfig()` re-filters and re-emits `_latestFullReport` whenever called, so changes to `reportThreshold` are reflected immediately to listeners without requiring a new scan.
- Also fixed the pre-existing `_autoScan` sync bug: `_autoScan = newConfig.autoScan` now runs unconditionally before the `autoScanChanged` branch (previously it only ran inside `if (autoScanChanged && _status != disabled)`), so a disabled engine that is later re-enabled starts the scheduler with the correct settings.

**New tests in `test/engine/leak_engine_test.dart`** (`group('reportThreshold filtering')`):
1. Warning finding excluded when threshold is `critical` (non-monotonic growth produces `warning`).
2. Warning finding passes when threshold is `warning`.
3. `updateConfig` reactive re-emission: lower threshold to `info` → finding appears on stream; raise to `critical` → still appears (critical index passes).

### Fix 2 (IMPORTANT) — Live `showOverlay` toggle

**Problem:** `LeakRadarOverlay.build` short-circuited at `if (!widget.show) return widget.child` but the rest of the build path never re-checked `LeakRadar.configListenable`. Calling `LeakRadar.updateConfig(config.copyWith(showOverlay: false))` after mount had no visible effect.

**Changes to `lib/src/ui/leak_radar_overlay.dart`:**
- Added `import '../config/leak_radar_config.dart'` (needed for the `ValueListenableBuilder` type parameter).
- `build()` now returns a `ValueListenableBuilder<LeakRadarConfig>` after the fast-path `widget.show` check.
- The builder lambda checks `config.showOverlay` and either returns `widget.child` (hidden) or delegates to the new private `_buildOverlay(BuildContext)` method.
- All previous badge / animation / stack code moved into `_buildOverlay`.

**New tests in `test/ui/leak_radar_overlay_test.dart`:**
1. `showOverlay` toggle off hides badge on a mounted overlay.
2. `showOverlay` toggle on shows badge on a mounted overlay (start hidden → toggle to visible).

Both tests use `LeakRadar.updateConfig` (which updates `_configNotifier` even without an engine), with `await LeakRadar.dispose()` guard in setUp / tearDown to keep tests isolated.

### Fix 3 (MINOR) — Color token consistency in `leak_radar_screen.dart`

**Problem:** `_Chip.build` used `Color.fromRGBO(46, 227, 155, ...)` — off-by-one from the canonical `LeakRadarColors.accent = Color(0xFF2fe39b)` = RGB(47, 227, 155). `_BottomBar.build` used the correct `47` value but as a raw literal, duplicating the token.

**Changes to `lib/src/ui/leak_radar_screen.dart`:**
- `_Chip` active color and border now use `LeakRadarColors.accent.withValues(alpha: 0.18)` / `0.55`.
- `_BottomBar` `boxShadow` now uses `LeakRadarColors.accent.withValues(alpha: 0.25)`.
- Removed `const` from the `BoxShadow` and its containing list (required since `withValues` is a method call, not a const constructor).

**Outcome:** `flutter analyze` — no issues. All 204 tests pass (192 pre-existing + 5 new for B5 overlay-toggle + threshold-filter coverage + 7 B5 pre-existing new tests).
