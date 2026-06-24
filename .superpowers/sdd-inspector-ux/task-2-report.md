# Task 2 Report — Engine API + Clear Leaks Menu Action

## Status: DONE_WITH_CONCERNS

## Commit hash
`d388c6a` — `feat(engine,ui): clearLeaks API and overflow menu action`

**Branch concern (see below):** the commit is on `feat/leak-graph-phase1`, not `feat/inspector-clear-and-swipe`.

## Test summary
19 engine tests pass (17 pre-existing + 3 new) · 13 UI widget tests pass (12 pre-existing + 1 new) · `flutter analyze` clean, no issues.

## What was implemented

### A — `SampleHistory.clear()`
Added `void clear() => _snapshots.clear();` to
`lib/src/analysis/sample_history.dart`.

### B — `LeakEngine.clearLeaks()`
Added before `_filtered()` in
`lib/src/engine/leak_engine.dart`:
- clears `_registry` and `_history`
- calls `_degraded('clear')` to produce an empty report
- sets both `_latestFullReport` and `_latestFiltered`
- adds to `_reports` stream (guarded with `isClosed` check)

### C — `LeakRadar.clearLeaks()`
Added after `markDisposed` in `lib/src/leak_radar.dart`.
Uses `runSafely<void>`, delegates to `_engine?.clearLeaks()`.
No-op when engine is null.

### D — Overflow menu "Clear leaks"
In `lib/src/ui/leak_radar_screen.dart`:
- Added `clearLeaks` to `_HeapMenuAction` enum
- Added `PopupMenuItem` after 'Share report'
- Added exhaustive `case` in `onSelected`: calls `LeakRadar.clearLeaks()` then
  `setState(() => _report = LeakRadar.latest)` (guarded with `mounted`)

## Test deviation: stream event timing
The brief suggested `await Future<void>.value()` (one microtask). The broadcast
stream controller (sync: false) needs two microtask yields to deliver the event
to a listener. Added a second `await Future<void>.value()` in the engine test.
This matches the established pattern used in `updateConfig` tests — no
design concern.

## Concern: commit on wrong branch
The worktree at `/Users/aiva6306/Projects/+Sandbox/-Projects/flutter-leak-radar`
is checked out on `feat/leak-graph-phase1`, not `feat/inspector-clear-and-swipe`
as the brief stated. The commit `d388c6a` was made to `feat/leak-graph-phase1`.

To move it to the correct branch, run:
```bash
git checkout feat/inspector-clear-and-swipe
git cherry-pick d388c6a
git checkout feat/leak-graph-phase1
git reset --soft HEAD~1
```
