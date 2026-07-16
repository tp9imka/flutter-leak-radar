## 0.2.0

- New `series` module: `MetricSample`, `SeriesGap`, and `MetricSeries`
  (JSON with `schemaVersion: 1`), plus `assessSeries` producing a
  `SeriesAssessment` with a `SeriesVerdict` (`monotonicGrowth` /
  `plateau` / `noisy` / `insufficientData`). Implements the field-proven
  growth methodology: settle-window trim, gap-aware region selection
  (gaps are never bridged), init-free batch2-minus-batch1 delta,
  Theil-Sen robust slope, MAD-based noise thresholds, and end-shift
  checks so late crashes cannot read as growth and late rises cannot
  read as a bounded plateau. Honest degradation throughout: a signal
  that cannot be truthfully computed reads `insufficientData` / null —
  never a plausible number.

## 0.1.2

- Optional `dedupKey` on `Tracer.trace` / `traceAsync` / `start` — a
  caller-supplied signature (e.g. arguments) marking repeated invocations of the
  same operation. `SpanKeyStatsSnapshot.duplicateCount` reports how many spans
  repeated a previously-seen signature for a key (bounded to ~1024 signatures),
  distinct from any statistical "hot" heuristic. `Span.dedupKey` carries the
  joined signature.

## 0.1.1

- Docs only (no code change): document the per-key `SpanKeyStatsSnapshot`
  metrics — `callsPerSecond`, `avgInterCallIntervalMicros`, `meanMicros`,
  `maxMicros`, `totalMicros`, `firstStartMicros`, `lastStartMicros` — in the
  README.

## 0.1.0

- Initial release: Span model, LatencyHistogram, OutlierRing,
  TraceRecorder, TraceSnapshot, Tracer façade with Zone-based nesting.
- Added per-key call metrics to `SpanKeyStatsSnapshot`:
  `firstStartMicros`, `lastStartMicros`, `avgInterCallIntervalMicros`
  (null when count < 2), `callsPerSecond` (null when count < 2 or
  window is zero), `meanMicros`, `maxMicros`, `totalMicros` — all
  exact (no bucket approximation).
