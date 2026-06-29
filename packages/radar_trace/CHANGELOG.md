## 0.1.0

- Initial release: Span model, LatencyHistogram, OutlierRing,
  TraceRecorder, TraceSnapshot, Tracer façade with Zone-based nesting.
- Added per-key call metrics to `SpanKeyStatsSnapshot`:
  `firstStartMicros`, `lastStartMicros`, `avgInterCallIntervalMicros`
  (null when count < 2), `callsPerSecond` (null when count < 2 or
  window is zero), `meanMicros`, `maxMicros`, `totalMicros` — all
  exact (no bucket approximation).
