# Runtime MVP — Blockers, Deferred Items & Next Steps

> Authoritative record from the subagent-driven build of
> `docs/plans/2026-06-23-flutter-leak-radar-runtime-mvp.md` on branch `feat/runtime-mvp`.

## Build outcome

- **All 13 tasks (0–12) complete.** Each task: fresh implementer subagent → task review (spec + quality) → fix loop where needed. Whole-branch review (Opus) at the end.
- **54 tests pass; `flutter analyze` clean** (Flutter 3.38 / Dart 3.10).
- **No Critical issues.** Final whole-branch review passed *with fixes*; both must-fixes were resolved in `7fcc5af`:
  1. **Growth warm-up guard** — `seriesFor` zero-pads absent classes, so a brand-new class produced a series like `[0,0,5]` and tripped on first sight. Growth now requires the class to be live in ≥2 snapshots and baselines over non-zero samples. (Resolves spec open-question §11.1.)
  2. **Retaining-path value types** — added `==`/`hashCode` to `RetainingHop`/`RetainingPathView` and made `RetainingPathView.toJson` omit a null `gcRootType`.

## Open blockers

- **None block the MVP.** (Push target `origin` and toolchain resolved at setup.)
- **`VmHeapProbe` real behavior is not covered by automated tests.** The integration test no-ops when no VM service is present (e.g. in `flutter test`/CI). The quarantined vm_service I/O layer (capture via `getAllocationProfile(gc:)`, retaining paths) must be validated **on-device in `--profile`** — see Next Steps #1.

## Deferred follow-ups (none block the MVP; from per-task + final review)

**A. Before the retaining-path UI lands** (the whole `retainingPath` code path is currently unused in the MVP — the screen does not yet fetch paths):
- `maxRetainingPathRequests` ctor param is dead — wire it as the caller-side per-cycle budget or remove.
- `parentMapKey` cast should be `is InstanceRef ? … : …` rather than relying on the outer catch.
- `retainingPath` re-runs a full `getAllocationProfile` per call to resolve class→classRef — cache the name→`ClassRef` map from `capture`.
- `_connectFailed` latch can brick the probe after a transient socket drop + failed reconnect — add a recovery path (spec §9 promises lazy reconnect).
- Integration test covers only `isAvailable`+`capture`; `retainingPath`/`dispose` need on-device validation.

**B. Precise registry:**
- `markDisposed` stamps real `DateTime.now()` while `collectLeaks` injects `now` → the `disposalGrace == Duration.zero` short-circuit is a bandage. Add an injectable clock and a positive-grace test.
- `track` keys by `identityHashCode` (collision = silent overwrite) — move to an `Expando`/`WeakReference` keying for robustness.

**C. Detection polish:**
- `LeakAnalyzer.analyze` calls `DateTime.now()` for `capturedAt` (minor purity wart) — inject a clock or use `history.last.capturedAt`.
- `SuspectSet.ruleFor` returns on the FIRST matching `ignore` (matches the plan) — footgun: a user can't un-ignore a sub-pattern. Revisit when user-overridable rules land.
- `LeakEngine` overlap-degraded report carries the current status — consider a dedicated `busy` status.

**D. Cosmetic:** path-comment convention atop lib files (inconsistent — decide whether to strip project-wide).

## Deferred MVP scope (in the spec, intentionally NOT in this slice → follow-up plan)

- **Triggers:** periodic `ScanScheduler` + `LeakRadarNavigatorObserver` (on-navigation), `AutoScan` config.
- **UI:** draggable overlay badge, growth sparkline, lazy retaining-path expansion tile.
- **Export/share:** `LeakReport.toJson()`/`toMarkdown()` exist; `LeakRadar.exportToFile()` + `share_plus` button deferred.
- **Facade:** `overlay()`, `navigatorObserver`, `exportToFile()` (currently only `init`/`scan`/`track`/`markDisposed`/`reports`/`latest`/`status`/`dispose`).

## Next steps (for review)

1. **On-device validation (highest priority):** run the `example/` app (after `flutter create .` to add a platform) or wire `LeakRadar` into a real app, launch `--profile`, and confirm `capture` returns real per-class live counts and the leaky screen surfaces as a finding.
2. **Follow-up plan #2 (runtime):** triggers + overlay + sparkline + export — the deferred MVP scope above.
3. **Sub-project 2:** the `flutter_leak_radar_lint` custom_lint plugin (spec already written: `docs/specs/2026-06-23-flutter-leak-radar-lint-design.md`).
4. **Calibrate `SuspectSet.defaults()`** against a real app to tune false positives/negatives.
