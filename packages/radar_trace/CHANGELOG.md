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
