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
  `<out>.<label>.analysis.json` leak-analysis files. Each carries a
  `captureStatus` (`ok` / `partial` / `failed`) and, when not `ok`, a
  `captureError` — so a failed capture is distinguishable from an
  un-requested snapshot, and never aborts the run.
- **`metadata`** — start time, Dart version, mode (only when supplied or
  derivable from `--cmd`; otherwise absent), command line, resolved project
  packages, and `completed` (`false` with an `abortReason` on a partial run
  flushed after an error or interrupt).

A run is resilient: a checkpoint RPC blip degrades that checkpoint to a
`failed`/`partial` marker and continues, and an interrupt (Ctrl-C / SIGTERM)
reaps the spawned child and still flushes a partial `run.json`
(`completed: false`, `abortReason: interrupted`).

## The `gate` verb

```shell
dart run radar_ci gate run.json --baseline base.json
```

A verdict-based CI gate. It **fails (exit 3)** when either a tracked memory
signal (`dart.heap.used` / `dart.external` / `process.rss`) is certified as
monotonic growth, or the baseline comparison over the freshest checkpoint
analysis surfaces a NEW cluster anchored in your own code. `insufficientData` /
`noisy` / `plateau` never fail. Byte-absolute thresholds
(`--max-new-clusters` / `--max-total-clusters` / `--max-class-growth` /
`--max-heap-growth`, gated at `--min-confidence`) are opt-in. A gate that
cannot be evaluated (partial run without `--allow-partial`, unreadable or
incomparable baseline, no analysis to compare) refuses with **exit 2** and a
distinct `⛔` line — never a silent pass, never all-NEW.

`--write-baseline <file>` records a baseline from the freshest analysis.
Writing one on a **failing** run is allowed but prints a warning: later runs
will treat those clusters as known and stop flagging them, so prefer writing
baselines from a green run.

## The `report` verb

```shell
dart run radar_ci report run.json --format md   # or github | json
```

A unified memory + leak report: line 1 is the overall verdict (worst of the
series and cluster gates), then the featured clusters (reusing `leak_graph`'s
renderer), the per-signal series table, and folded details. `report` is
informational — it renders the verdict but is never the enforcer (exit `0`
unless the run itself is unreadable). Its cluster view always uses the default
`heuristic` min-confidence, so it may read FAIL where `gate --min-confidence
confirmed` passes.

## Exit codes

`0` ok · `1` usage error · `2` tool failure (spawn/attach/connection, a
partial/aborted run, or a `gate` that could not be evaluated) · `3` `gate`
failed.

## Follow-ups (planned)

- **Decouple snapshot/analysis from the sampling hot path.** Heap dumps and
  in-process `leak_graph` analysis currently run inline at each checkpoint,
  pausing sampling; once moved off the hot path, the `--snapshot-every`
  default will drop to start/end-only.
- **Worker-isolate heaps are not analysed.** Snapshots and analysis target the
  main isolate only; leaks confined to spawned isolates are not yet surfaced.
