# Changelog

This is a **suite-level overview** of notable changes across the Radar
monorepo. Each package keeps its own authoritative, version-numbered
changelog — this file exists to summarize what changed across the suite as a
whole between rounds, and to point you at the right per-package changelog for
exact version numbers and API-level detail.

## Unreleased

- **Radar Desktop** (`radar_desktop`) — a new standalone macOS-first desktop
  app for analyzing the suite's captures, built on the shared
  `radar_workbench` engine.
- **Connected mode** — Radar Desktop can attach live to a running app's Dart
  VM Service over a `ws://` URI, unlocking live Performance/Stability tabs,
  on-demand heap capture, and Force GC directly from the desktop app.
- **Android native profiling** — a new lane for native-heap analysis:
  heapprofd/Perfetto capture over `adb`, per-module still-live analysis,
  checkpoint compare/diff, and an FFI-allocations view, backed by two new
  internal packages, `radar_native` (pure-Dart models) and
  `radar_native_host` (host-side Perfetto/`adb` tooling).
- **Native symbolization** — resolves build-id-matched unstripped `.so`
  files to function names via `llvm-symbolizer`, exposed both as the
  `symbolize` CLI in `radar_native_host` and as an in-app action in Radar
  Desktop.
- `radar_native` is now explicitly gated `publish_to: none` (it's an internal
  model package, not a public API).

## Per-package changelogs

- [`packages/radarscope/CHANGELOG.md`](packages/radarscope/CHANGELOG.md)
- [`packages/flutter_leak_radar/CHANGELOG.md`](packages/flutter_leak_radar/CHANGELOG.md)
- [`packages/flutter_perf_radar/CHANGELOG.md`](packages/flutter_perf_radar/CHANGELOG.md)
- [`packages/flutter_leak_radar_lint/CHANGELOG.md`](packages/flutter_leak_radar_lint/CHANGELOG.md)
- [`packages/leak_graph/CHANGELOG.md`](packages/leak_graph/CHANGELOG.md)
- [`packages/radar_trace/CHANGELOG.md`](packages/radar_trace/CHANGELOG.md)
- [`packages/radar_ui/CHANGELOG.md`](packages/radar_ui/CHANGELOG.md)

See [`docs/PUBLISHING.md`](docs/PUBLISHING.md) for current published versions
and the release process.
