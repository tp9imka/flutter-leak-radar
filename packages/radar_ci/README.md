# radar_ci

Headless CI front door for **flutter-leak-radar**. Attaches to (or spawns) a
running Dart/Flutter app, samples its memory into gap-aware time series,
captures allocation profiles and optional heap snapshots at evenly spaced
checkpoints, and emits a portable `run.json` for downstream assessment.

Pure Dart — no Flutter dependency. Runs anywhere the Dart VM does.

---

## The `run` verb

```shell
# Attach to an already-running VM service:
dart run radar_ci run --vm-uri ws://127.0.0.1:8181/TOKEN=/ws -o run.json

# Or spawn the app and attach automatically:
dart run radar_ci run --cmd "flutter run --profile -d <device>" -o run.json
```

`radar_ci` discovers the VM-service URI from `flutter run --machine`
`app.debugPort` events, falling back to the `The Dart VM service is listening
on …` line (the same wording `adb logcat` and plain `dart --enable-vm-service`
emit — parsed by `radar_native_host`'s `parseLogcatVmServiceUris`).

### Key options

| Flag | Default | Purpose |
| --- | --- | --- |
| `--duration` | `3m` | Total run time (min 2m unless `--allow-short`). |
| `--sample-interval` | `5s` | Time between memory samples. |
| `--settle` | `30s` | Warm-up window trimmed before assessment. |
| `--checkpoints` | `3` | Interior checkpoints, plus `start`/`end`. |
| `--snapshot-every` | `1` | Heap snapshot every Nth checkpoint (`0` = none). |
| `--exec` / `--call-extension` | — | Driver hook fired between checkpoints. |
| `--project-packages` | auto | App package names scoping leak analysis. |

The shipped defaults produce well over the 12 post-settle samples that
radar_trace's Mann–Kendall growth test needs. If your overrides fall below that
floor, `radar_ci` prints a warning: the resulting run would read
`insufficientData` rather than a growth verdict.

## Output

`run.json` (`RadarRunDocument`, `schemaVersion` 1) carries:

- **`series`** — `dart.heap.used`, `dart.heap.capacity`, `dart.external`
  (per-isolate summed) and `process.rss`, each gap-aware: an RPC failure
  during sampling records a `SeriesGap`, never a fabricated value.
- **`checkpoints`** — `start` … `end`, each with a top-N allocation profile
  and, when captured, sibling `<out>.<label>.data` heap snapshots and
  `<out>.<label>.analysis.json` leak-analysis files.
- **`metadata`** — start time, Dart version, mode, command line, and the
  resolved project packages.

## Exit codes

`0` ok · `1` usage error · `2` tool failure (spawn/attach/connection).
