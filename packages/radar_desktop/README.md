# radar_desktop

**Radar Desktop** — a macOS-first desktop app for analyzing the Radar suite's
captures: heap dumps, Perfetto traces, and live Dart VM Service connections.
It is an **app, not a published pub.dev package** (`publish_to: none`), built
on [`radar_workbench`](../radar_workbench/) (the shared analysis engine),
[`radar_ui`](../radar_ui/) (design system), and
[`radar_native`](../radar_native/) (native-heap models).

## Three modes

- **Offline** — import a heap-snapshot dump or a Perfetto `.pftrace` capture
  from disk and analyze it with no running app or device attached: class
  histograms, retaining paths, snapshot diffing, and trend views.
- **Connected mode** — attach to a running app's Dart VM Service over a
  `ws://` URI (the same URI `flutter run` prints) to unlock **live**
  Performance and Stability tabs, on-demand heap capture, and a **Force GC**
  action, all without leaving the desktop app.
- **Android Profiling** — capture native-heap data from an Android device via
  `adb` + heapprofd + Perfetto, then work with it entirely on desktop:
  per-module still-live analysis, checkpoint compare/diff, an FFI-allocations
  lane, and **native symbolization** (resolve build-id-matched unstripped
  `.so` files into function names via `llvm-symbolizer`, either through the
  in-app "Resolve from .so directory" action or the standalone `symbolize`
  CLI in `radar_native_host`).

## Running it

From this package directory:

```bash
flutter run -d macos
```

or build a standalone app bundle:

```bash
flutter build macos
```

## Optional external tools

Android Profiling and native symbolization shell out to a few external
binaries. Each has an explicit override via environment variable; without
them, the relevant feature reports a clear "not available" error instead of
silently degrading.

| Tool | Purpose | Override |
|---|---|---|
| `trace_processor` | Parses Perfetto `.pftrace` captures | `RADAR_TP_BIN` |
| `llvm-symbolizer` (NDK) | Resolves addresses to function names | `RADAR_LLVM_SYMBOLIZER` |
| `llvm-readelf` (NDK) | Reads the build-id from an unstripped `.so` | `RADAR_READELF` |
| `adb` | Drives on-device heapprofd capture | resolved from `PATH` |

See the root [README](../../README.md) for how Radar Desktop fits into the
rest of the suite, and [`radar_native_host`](../radar_native_host/) for the
`symbolize` CLI this app's in-app symbolization is built on.
