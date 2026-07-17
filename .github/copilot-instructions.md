# Review instructions for flutter-leak-radar

This is a Flutter/Dart observability suite (memory-leak detection, CI gating,
Android native profiling). It is a measurement tool, so review with one value
above all others: **a plausible-but-wrong number is worse than no number.**

## Honesty rules (flag any violation as a bug, not a nit)

- A value that cannot be truthfully computed must read as absent / `null` /
  `insufficientData` / "not measured" — never `0`, never a guess. Parsers that
  return 0 on a format miss are bugs (`SampleValue` in radar_native_host is the
  reference pattern: parsed-or-unmeasured).
- Measurement gaps (`SeriesGap`) are never interpolated, bridged, or drawn
  through. A chart or assessment that spans a gap fabricates data.
- UI must label heuristics and sources: shallow bytes are labeled "shallow";
  the project-package detection source is always shown; degraded states get an
  explicit banner, not an empty view.
- A CLI gate must never exit 0 when something it was asked to evaluate could
  not be evaluated — refusal is exit 2 with a message naming the check.

## Hard contracts (breaking these breaks consumers)

- Exit codes, suite-wide: `0` ok · `1` usage error · `2` tool failure ·
  `3` gate failed. Do not invent new meanings or invert classes.
- `pathSignature` and `GraphHop`/`GraphRetainingPath` `==`/`hashCode` in
  `leak_graph` are byte-stable — CI baselines key on them. The golden test in
  `test/analysis/signature_stability_test.dart` must never be weakened; any
  change that shifts cluster identity needs a CHANGELOG re-baseline note.
- All persisted JSON carries `schemaVersion`; readers tolerate older, refuse
  newer. New fields must be additive-tolerant (absent → default).
- Growth verdicts come from `radar_trace`'s `assessSeries` (Mann–Kendall
  certified). Never add ad-hoc "is it growing" heuristics; the false-positive
  bound is regression-tested.

## Structure and style

- Pub workspace, 13 packages. Pure-Dart analysis lives at or below
  `leak_graph`/`radar_trace`/`radar_native` (no Flutter imports there);
  `radar_workbench` views compile into the DevTools *web* extension — no
  `dart:io` in any library it imports (io helpers go in `leak_graph/io.dart`
  or host packages).
- Shared UI changes must work in BOTH hosts (DevTools extension + Radar
  Desktop) — each has its own navigation wiring. Anything touching
  radar_workbench/radar_ui/radar_desktop needs all four UI suites green:
  workbench, leak_graph, desktop, and devtools via
  `flutter test --platform chrome`.
- Widget layouts must be width-safe (no RenderFlex overflow at 320+ for
  radar_ui, 722+ for desktop panes); `test/layout_width_test.dart` shows the
  pattern. `pumpAndSettle` hangs when the desktop shell is mounted (first-run
  guide animates forever) — tests inject a seen-guide and use `pump(300ms)`.
- Effective origin (anchor-else-declared) is the ownership rule everywhere a
  package/origin surfaces (chips, filters, grouping, ranking). A surface using
  declared-only origin where an anchor exists is a bug.
- Immutability by default; hand-rolled `==`/`hashCode`/`copyWith` (no freezed
  / json_serializable). Minimal comments — only non-obvious constraints.
- Conventional commits; TDD is the norm — expect a failing test alongside
  every behavior change, and treat a logic change without one as a finding.

## Things NOT to flag

- The committed DevTools bundle under
  `flutter_leak_radar/extension/devtools/build/` (generated, shipped
  deliberately; rebuilt via `tool/build_devtools_extension.sh`).
- `resolution: workspace` stripping done by `tool/publish.sh` at publish time.
- Control-character (U+001F) signatures in radar_native and the marked
  do-not-reformat SQL in the trace_processor queries.
