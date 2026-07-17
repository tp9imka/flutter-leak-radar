# radar_native_host

Host-side tooling for the native (Android heapprofd/Perfetto) memory lane:
parses `.pftrace` captures into [`radar_native`](../radar_native/) model
checkpoints, drives on-device capture over `adb`, and resolves native
symbols. Unlike the pure-Dart `radar_native` package, `radar_native_host` is
free to use `dart:io` and shell out to external binaries.

## What it does

- **Perfetto parsing** — runs an external `trace_processor` binary over a
  `.pftrace` capture and maps the resulting rows into `radar_native`
  checkpoints (`PerfettoTraceProcessorParser`, `PerfettoProfileMapper`).
- **Device capture** — enumerates devices and drives heapprofd capture
  sessions over `adb` (`AdbDevices`, `AdbRunner`, `DeviceProbe`,
  `NativeHeapCapture`, `HeapprofdConfig`).
- **Symbolization** — reads the build-id from an unstripped `.so`
  (`BuildIdReader`), resolves addresses to function names via
  `llvm-symbolizer` (`Symbolizer`), and assembles a `SymbolStore`
  (`SymbolStoreBuilder`).

## `symbolize` CLI

```bash
dart run radar_native_host:symbolize \
  --trace capture.pftrace \
  --so libapp.so [--so libB.so ...] [--so-dir path/to/libs] \
  --out symbols.json \
  [--tp-bin trace_processor] [--symbolizer llvm-symbolizer] [--readelf llvm-readelf]
```

Each external tool can also be supplied via environment variable instead of a
flag, which is what [`radar_desktop`](../radar_desktop/)'s in-app
symbolization uses:

| Flag | Env var override |
|---|---|
| `--tp-bin` | `RADAR_TP_BIN` |
| `--symbolizer` | `RADAR_LLVM_SYMBOLIZER` |
| `--readelf` | `RADAR_READELF` |

A missing tool (no flag, no env var, not on `PATH`) fails with a clear error
naming which one to set — it never silently skips symbolization.

## Native-lane CLI verbs

The field-proven Android trend workflow, as automatable verbs. Every sampler
goes through the `AdbRunner` seam and follows the **parsed-or-unmeasured rule**:
a `dumpsys`/`/proc` format miss reads *not measured* (a gap), never a fake `0`.

```shell
# Sample dumpsys meminfo / /proc / fd / thread trends into a session dir.
# Overnight-robust: adb reconnect, pid re-resolve, gap markers, periodic flush.
dart run radar_native_host:sample --package com.example.app \
  --interval 5s --duration 8h --out before/ [--device SERIAL]

# Append a timestamped label to a running or finished session.
dart run radar_native_host:mark --session before/ "reconnect"

# heapprofd capture with preflight (availability + profileable + non-empty).
dart run radar_native_host:capture --package com.example.app --out capture.pftrace

# Native profiles → json/md.
dart run radar_native_host:diff a.pftrace b.pftrace

# Route one session to a per-column leak-bucket verdict…
dart run radar_native_host:triage before/

# …or diff the before-fix and after-fix sessions, column by column.
dart run radar_native_host:triage before/ --compare after/
```

`triage`'s router attributes growth to a bucket (java / native-malloc /
graphics / fd / thread) ranked within its unit family — byte rates and count
rates are never cross-compared. The same session JSON imports into **Radar
Desktop**'s Device Monitor pane, and `radar_ci run --native-package` co-drives
this sampling during a full CI run (see [`radar_ci`](../radar_ci/)).

## Exit codes

Every verb (`sample`, `mark`, `capture`, `diff`, `triage`, `symbolize`) follows
the initiative-wide contract, so a retry-on-tool-failure CI wrapper behaves the
same whichever verb it drives:

| Code | Meaning |
|---|---|
| `0` | Success. |
| `1` | Usage error — a bad flag, a missing required argument, an unknown `--format`, a session directory with no `timeline.json`, or a capture precondition that a different invocation would fix (device API too low, package not profileable, an empty capture, a `trace_processor` binary that was never configured). |
| `2` | Tool failure — a genuine runtime failure that a retry might clear: a corrupt/unwritable `timeline.json`, an `adb` or `trace_processor` process error, or a `sample` session the loop ended on an internal error (`endReason: error`). |

`sample` returns `0` for both a `completed` and an interrupted (`Ctrl-C`)
session — an interrupted overnight run is still valid data — and only `2` when
the loop itself failed. This matches `radar_ci`'s `GateExit` (which adds `3` for
a gate-threshold violation) and `leak_graph`'s `analyze`/`leak_diff`/`capture`.

## Internal package

`radar_native_host` is **not published to pub.dev** (`publish_to: none`). It
is a development/analysis tool consumed by Radar Desktop, not an SDK meant
for embedding in end-user apps.

See the root [README](../../README.md) for how this fits into the wider
Radar suite, and [`radar_desktop`](../radar_desktop/) for the app that
wraps this CLI's symbolization and capture flows in a UI.
