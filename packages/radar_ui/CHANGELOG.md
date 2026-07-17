# Changelog

## 0.4.0

- `RadarTimeSeriesChart`: a dark-only multi-series time chart. Plots several
  `ChartSeries` on a shared time axis with adaptive (s/m/h) tick labels, a
  wrapping legend, checkpoint `ChartMark` verticals, shaded settle
  `ChartWindow`s, and an optional horizontal `threshold` line. Honest by
  construction: measurement gaps render as line BREAKS and are never bridged,
  and `normalizePerSeries` scales each series to its own range for multi-unit
  overlays (dropping the threshold, which then has no shared value). Empty and
  single-point inputs are safe and it never overflows at 320px or wider.
  Separate from `RadarTrendChart`, which stays a single-series Y-only
  sparkline.

## 0.3.0

- `RadarOrigin` + `OriginTokens`: an ownership palette (project/dependency/
  framework/sdk/unknown) shared across chips, group headers, and the
  native module legend. Project is violet — deliberately not `accent`,
  which always means healthy/negative-delta.
- `OriginChip` and `TriageChip` (NEW / KNOWN / ACK / GONE) widgets, both
  built on `RadarTag`.

## 0.1.1

- `RadarFilterChip` and `RadarSortHeader` now render a Material ink ripple on
  tap for responsive feedback (no API or layout change).

## 0.1.0

- Initial release: color tokens, typography, density,
  severity mapping, and primitive widgets for the
  Flutter Radar design system.
