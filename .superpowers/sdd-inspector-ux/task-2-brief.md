# Task 2 Brief — Engine API + Clear Leaks Menu Action

## Context
Package `packages/flutter_leak_radar` in repo
`/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar`.
Branch: `feat/inspector-clear-and-swipe` (already checked out). Commit there.

## Files to read BEFORE writing anything
1. `packages/flutter_leak_radar/lib/src/analysis/sample_history.dart`
2. `packages/flutter_leak_radar/lib/src/engine/leak_engine.dart`
3. `packages/flutter_leak_radar/lib/src/leak_radar.dart`
4. `packages/flutter_leak_radar/lib/src/ui/leak_radar_screen.dart`
5. `packages/flutter_leak_radar/lib/src/model/leak_report.dart`
6. `packages/flutter_leak_radar/test/engine/leak_engine_test.dart`
7. `packages/flutter_leak_radar/test/ui/leak_radar_screen_test.dart`

## Required changes

### A) `SampleHistory.clear()` — new method
File: `packages/flutter_leak_radar/lib/src/analysis/sample_history.dart`
Add:
```dart
/// Empties the snapshot ring buffer.
void clear() => _snapshots.clear();
```

### B) `LeakEngine.clearLeaks()` — new method
File: `packages/flutter_leak_radar/lib/src/engine/leak_engine.dart`
Add after the `scan()` method (before `_filtered`):
```dart
/// Resets all accumulated leak state without stopping the engine.
///
/// Clears the precise registry, empties the snapshot history, sets both the
/// full and filtered latest reports to an empty report, and emits the empty
/// report on [reports] so the UI updates immediately.
void clearLeaks() {
  _registry.clear();
  _history.clear();
  final empty = _degraded('clear');
  _latestFullReport = empty;
  _latestFiltered = empty;
  if (!_reports.isClosed) _reports.add(empty);
}
```
Note: `_degraded` already exists and produces a `LeakReport` with empty
findings + current timestamp + given trigger + `_status`. Use it.

### C) `LeakRadar.clearLeaks()` — new facade method
File: `packages/flutter_leak_radar/lib/src/leak_radar.dart`
Add after `markDisposed` (around line 151):
```dart
/// Resets all accumulated leak state visible in the UI.
///
/// Clears the engine's precise registry, snapshot history, and latest
/// report, then emits an empty [LeakReport] on [reports] so the UI updates.
/// A no-op when the engine is not running. Never throws.
static void clearLeaks() =>
    runSafely<void>(
      () => _engine?.clearLeaks(),
      fallback: null,
      logger: _logger,
    );
```

### D) Wire "Clear leaks" into the overflow menu
File: `packages/flutter_leak_radar/lib/src/ui/leak_radar_screen.dart`

**Step 1:** Add `clearLeaks` to the `_HeapMenuAction` enum (already has
`heapSnapshot, share`):
```dart
enum _HeapMenuAction { heapSnapshot, share, clearLeaks }
```

**Step 2:** In `_buildAppBar()`, add a new `PopupMenuItem` to `itemBuilder`
after the 'Share report' item:
```dart
PopupMenuItem(
  value: _HeapMenuAction.clearLeaks,
  child: Text(
    'Clear leaks',
    style: LeakRadarText.label.copyWith(
      color: LeakRadarColors.text100,
    ),
  ),
),
```

**Step 3:** In the `onSelected` switch, add a `case`:
```dart
case _HeapMenuAction.clearLeaks:
  LeakRadar.clearLeaks();
  if (mounted) setState(() => _report = LeakRadar.latest);
```

The screen already listens to `LeakRadar.latest` (seeded in `initState`) and
displays via `_report`. After `clearLeaks()`, the engine emits on its stream,
but the screen doesn't subscribe to `LeakRadar.reports` — it uses
`_report` local state. So we must call `setState(() => _report = LeakRadar.latest)`.
`LeakRadar.latest` returns the engine's `_latestFiltered` which is now the
empty report. This ensures the list clears immediately.

## Tests to write

### Engine tests
File: `packages/flutter_leak_radar/test/engine/leak_engine_test.dart`

Add a `group('LeakEngine.clearLeaks', ...)`:

1. `clearLeaks empties registry and history, emits empty report` —
   Run 3 scans to build history, collect emitted reports, call
   `clearLeaks()`, await a microtask, assert the latest emitted report has
   `findings.isEmpty` and `trigger == 'clear'`.
2. `SampleHistory.clear empties snapshots` —
   Create a `SampleHistory`, add a snapshot, call `clear()`, assert
   `length == 0`.
3. `LeakRadar.clearLeaks is no-op when engine is null` —
   Call `LeakRadar.dispose()`, then `LeakRadar.clearLeaks()` — must not throw.

### Widget test
File: `packages/flutter_leak_radar/test/ui/leak_radar_screen_test.dart`

Add a `group('Clear leaks', ...)`:

1. `tapping Clear leaks in overflow menu empties the list` —
   Seed 3 scans with a growing `HomeBloc` so a finding shows. Pump
   `LeakRadarScreen`. Verify `HomeBloc` is visible. Open overflow menu
   (`find.byTooltip('More')`), tap the 'Clear leaks' item, call
   `pumpAndSettle()`. Assert `find.text('HomeBloc')` is gone and
   `find.text('No leaks detected')` is visible.

## Global constraints
- Never-throw into host: `runSafely`/`runSafelyAsync` in facade; debug/profile only, release no-op; hand-rolled immutable (no freezed); minimal comments (only non-obvious ones); lines ≤ 80 chars; no `print`; null safety: no `!` unless guaranteed non-null; `const` constructors wherever possible.

## TDD order
1. Write ALL tests first (they will fail for missing `clearLeaks` methods)
2. Run tests to verify RED
3. Implement A → B → C → D
4. Run tests — all GREEN
5. Run `flutter analyze packages/flutter_leak_radar` — must be clean

## Report contract
Write your report to:
`/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar/.superpowers/sdd-inspector-ux/task-2-report.md`

Return status, commit hash(es), one-line test summary, and any concerns.
