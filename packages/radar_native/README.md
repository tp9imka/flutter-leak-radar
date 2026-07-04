# radar_native

Pure-Dart models and analysis for **native-heap** (Android heapprofd /
Perfetto) leak detection — a peer to [`leak_graph`](../leak_graph/), which
covers the Dart heap. `radar_native` has no `dart:io` or platform dependency;
it only defines data and pure functions over it, so it is trivially unit
testable and safe to share between the host CLI, `radar_native_host`, and
Radar Desktop.

## What it models

- **Native heap profiles** — checkpoints of native allocations grouped by
  module, callsite, and frame (`NativeHeapProfile`, `NativeFrame`,
  `NativeCallsite`, `NativeModule`).
- **Diffing** — comparing two checkpoints to find still-live growth
  (`NativeModuleDiff`, `NativeDiffStatus`, `NativeAllocationDiff`).
- **Summaries** — per-module still-live rollups (`NativeModuleSummary`,
  `NativeModuleKind`).
- **FFI allocation logs** — a separate lane for tracking raw FFI
  allocations (`FfiAllocationLog`).
- **Symbolization support** — a `SymbolStore` for mapping addresses to
  resolved symbols once `radar_native_host` has symbolized a trace.
- **Parsing** — turning a native profile / FFI log into the above models
  (`NativeProfileParser`, `FfiAllocationLogParser`).

## Internal package

`radar_native` is **not published to pub.dev** (`publish_to: none`). It exists
to be shared between the Radar tools that need native-heap analysis without
each reimplementing the model.

## Where it's used

- [`radar_native_host`](../radar_native_host/) — parses Perfetto captures
  into `radar_native` checkpoints and drives `adb`/heapprofd capture.
- [`radar_desktop`](../radar_desktop/) — the Android Profiling section of
  Radar Desktop renders these models.

See the root [README](../../README.md) for how this fits into the wider
Radar suite.
