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

## Internal package

`radar_native_host` is **not published to pub.dev** (`publish_to: none`). It
is a development/analysis tool consumed by Radar Desktop, not an SDK meant
for embedding in end-user apps.

See the root [README](../../README.md) for how this fits into the wider
Radar suite, and [`radar_desktop`](../radar_desktop/) for the app that
wraps this CLI's symbolization and capture flows in a UI.
