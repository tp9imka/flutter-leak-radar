# flutter-leak-radar — Follow-ups & Next Steps

Status (2026-06-23): **runtime MVP**, **lint plugin**, and **runtime follow-up** all merged to `main`
(PRs #1, #2, #3). Runtime pkg 111 tests, lint pkg 21 tests, both `analyze` clean.

## Blocked-on-you (one-step)

- **Restore CI workflow.** The plugin's GitHub Actions workflow was dropped from PR #2 because the
  push token lacks the `workflow` OAuth scope. To restore: `gh auth refresh -s workflow`, then
  `git show f05a718:packages/flutter_leak_radar_lint/.github/workflows/ci.yaml` (content) → re-add
  under `.github/workflows/` and push. (A root CI workflow for both packages is also worth adding.)

## Highest-value next step

- **On-device `--profile` validation.** The VM-service engine's real capture/retaining-path path is
  only covered by integration tests that no-op without a live service (CI). Run the `example/` app
  (after `flutter create .` to add a platform) in `--profile`, exercise the leaky screen, and confirm
  `capture` returns real per-class counts and findings surface. This is the proof the engine works
  end-to-end on a device.

## Runtime follow-up review minors (fast-follows)

- **`leak_radar_screen.dart` `ListTile.trailing` overflow** on narrow tiles (sparkline + severity in a
  Column) — paint warning, not a crash. Constrain / move the sparkline out of `trailing`. (Top item.)
- Precise findings (`notGced`/`notDisposed`, empty `series`) show no retaining-path tile — document or
  gate more semantically.
- `_share()` re-exports the file instead of reusing the export result (DRY).
- Periodic scans always `gc: true` (spec §11.2) — consider `gc: false` for trend ticks, force only on
  manual/navigation. Acceptable for a debug tool.
- VmHeapProbe reconnect: two failure modes have opposite retry policies — add a clarifying comment.

## Lint plugin follow-ups

- Switch `flutter_lints` → `lints` (pure-Dart plugin; cosmetic, no Flutter SDK dep today).
- Helper-method teardown FP: `dispose() { _disposeAll(); }` may false-positive (documented +
  `// ignore` escape hatch). Optionally follow one level of intra-class calls.
- Broaden to the deferred rules: `missing_remove_listener`, `unclosed_stream_controller`,
  `bloc_uncancelled_subscription`.
- Autofix indentation is hardcoded 4-space; cascade `stream..listen()` discarded-result is a FN;
  `isConstructorParam` name-only match is a rare FN on a same-named field initializer.

## Runtime MVP follow-ups (pre-existing)

- `LeakObjectRegistry`: inject a clock (markDisposed uses real `DateTime.now()`); move
  `identityHashCode` keying → `Expando`/weak keying.
- `LeakAnalyzer.analyze` uses `DateTime.now()` (minor purity wart).
- `SuspectSet.ruleFor` ignore-first precedence footgun (can't un-ignore a sub-pattern).
- `LeakEngine` overlap-degraded report carries current status — consider a `busy` status.

## Product

- Calibrate `SuspectSet.defaults()` against a real app (e.g. katim-connect-matrix) to tune
  false positives / negatives once on-device validation confirms the engine.
- README/pub polish (topics, description, dartdoc coverage) before any `pub publish`.
