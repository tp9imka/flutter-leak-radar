// lib/src/ui/widgets/frames_tab.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../../model/frame_stats.dart';

// ── Jank threshold ────────────────────────────────────────────────────────────

/// Budget per frame (16ms in microseconds).
const int _kFrameBudgetMicros = 16000;

/// Critical threshold: 33ms = 30fps or worse.
const int _kFrameCriticalMicros = 33000;

/// Number of worst frames shown in the worst-frames list.
const int _kWorstFrameCount = 5;

// ── Public widget ─────────────────────────────────────────────────────────────

/// Frames tab: jank tiles + frame-time bar timeline + percentiles + worst list.
class FramesTab extends StatelessWidget {
  /// Creates a [FramesTab] for the given [stats].
  const FramesTab({super.key, required this.stats, this.onReset});

  /// The frame timing snapshot to display.
  final FrameStatsSnapshot stats;

  /// Called when the user taps the reset button.
  ///
  /// When null, no reset button is shown — this keeps [FramesTab] usable
  /// standalone (e.g. in tests) without wiring a live [PerfRadar] engine.
  final VoidCallback? onReset;

  String _pct(int? p) {
    if (p == null) return '—';
    if (p < 1000) return '$pμs';
    return '${(p / 1000).toStringAsFixed(1)}ms';
  }

  String _jankPct() {
    if (stats.frameCount == 0) return '—';
    return '${(stats.jankCount / stats.frameCount * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        // ── Header: reset button ───────────────────────────────────────────
        if (onReset != null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: _ResetButton(onTap: onReset!),
          ),
          const SizedBox(height: 8),
        ],

        // ── 3 stat tiles ──────────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: RadarMetricTile(
                label: 'jank frames',
                value: '${stats.jankCount}',
                color: stats.jankCount > 0
                    ? RadarColors.critical
                    : RadarColors.accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: RadarMetricTile(
                label: 'jank %',
                value: _jankPct(),
                color: stats.jankCount > 0
                    ? RadarColors.warning
                    : RadarColors.accent,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: RadarMetricTile(
                label: 'frames',
                value: '${stats.frameCount}',
                color: RadarColors.text100,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Frame-time bar timeline ───────────────────────────────────────
        const _SectionLabel('FRAME TIMELINE'),
        const SizedBox(height: 6),
        _FrameTimeline(stats: stats),
        const SizedBox(height: 14),

        // ── Build / raster percentile tiles ──────────────────────────────
        const _SectionLabel('BUILD PHASE'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _PercentileTile(label: 'p50', value: _pct(stats.buildP50)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _PercentileTile(label: 'p95', value: _pct(stats.buildP95)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _PercentileTile(label: 'p99', value: _pct(stats.buildP99)),
            ),
          ],
        ),
        const SizedBox(height: 10),

        const _SectionLabel('RASTER PHASE'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _PercentileTile(
                label: 'p50',
                value: _pct(stats.rasterP50),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _PercentileTile(
                label: 'p95',
                value: _pct(stats.rasterP95),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _PercentileTile(
                label: 'p99',
                value: _pct(stats.rasterP99),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // ── Worst frames list ─────────────────────────────────────────────
        if (stats.recentFrames.isNotEmpty) ...[
          const _SectionLabel('WORST RECENT FRAMES'),
          const SizedBox(height: 6),
          _WorstFrames(stats: stats, fmtMicros: _pct),
        ],
      ],
    );
  }
}

// ── Reset button ──────────────────────────────────────────────────────────────

/// Small icon button that resets the frame counters for a fresh
/// measurement window. Styled to match the devtools-side reset action.
class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Reset frame counters',
      child: GestureDetector(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RadarColors.iconButtonBg,
            borderRadius: RadarDensity.iconButtonRadius,
            border: Border.all(
              color: RadarColors.iconButtonBorder,
              width: RadarDensity.hairline,
            ),
          ),
          child: const SizedBox(
            width: RadarDensity.iconButtonSize,
            height: RadarDensity.iconButtonSize,
            child: Icon(Icons.restart_alt, size: 15, color: RadarColors.text60),
          ),
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: RadarTypography.monoLabel.copyWith(letterSpacing: 0.8),
    );
  }
}

// ── Percentile tile ───────────────────────────────────────────────────────────

class _PercentileTile extends StatelessWidget {
  const _PercentileTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(color: RadarColors.hairline08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: RadarTypography.monoLabel),
          const SizedBox(height: 3),
          Text(value, style: RadarTypography.monoNumber.copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Frame-time bar timeline ───────────────────────────────────────────────────

/// Bar chart of the real recent frame-time ring ([FrameStatsSnapshot.recentFrames]).
///
/// One bar per recorded sample, chronological left-to-right.
/// Bar height is proportional to [FrameSample.totalMicros]; colour reflects
/// the existing budget/critical thresholds; the 16ms hairline is drawn over
/// the bars. When the ring is empty the placeholder is shown.
class _FrameTimeline extends StatelessWidget {
  const _FrameTimeline({required this.stats});

  final FrameStatsSnapshot stats;

  @override
  Widget build(BuildContext context) {
    final frames = stats.recentFrames;
    if (frames.isEmpty) {
      return Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RadarColors.bgSurface,
          borderRadius: RadarDensity.inputRadius,
        ),
        child: Text('No frames recorded yet.', style: RadarTypography.caption),
      );
    }

    final maxMicros = frames.fold(0, (m, f) => math.max(m, f.totalMicros));

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(color: RadarColors.hairline08),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Budget line label
          Padding(
            padding: const EdgeInsets.only(right: 4, bottom: 2),
            child: Text(
              '16ms',
              style: RadarTypography.monoLabel.copyWith(fontSize: 8),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final chartHeight = constraints.maxHeight;
                final budgetFraction = maxMicros > 0
                    ? _kFrameBudgetMicros / maxMicros
                    : 0.5;

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 16ms budget hairline
                    Positioned(
                      bottom: (chartHeight * budgetFraction).clamp(
                        0.0,
                        chartHeight,
                      ),
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 1,
                        color: RadarColors.warning.withValues(alpha: 0.4),
                      ),
                    ),
                    // Real bars — one per FrameSample
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final frame in frames)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0.5,
                              ),
                              child: FractionallySizedBox(
                                heightFactor: maxMicros > 0
                                    ? (frame.totalMicros / maxMicros).clamp(
                                        0.04,
                                        1.0,
                                      )
                                    : 0.1,
                                alignment: Alignment.bottomCenter,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _barColor(frame.totalMicros),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Color _barColor(int micros) {
    if (micros > _kFrameCriticalMicros) return RadarColors.critical;
    if (micros > _kFrameBudgetMicros) return RadarColors.warning;
    return RadarColors.accent.withValues(alpha: 0.65);
  }
}

// ── Worst frames list ─────────────────────────────────────────────────────────

/// Shows the top-[_kWorstFrameCount] frames from the real recent ring,
/// sorted by [FrameSample.totalMicros] descending.
///
/// Each row shows total time (color-graded), a build/raster sub-line, and
/// an honest BUILD-BOUND/RASTER-BOUND tag derived from which phase is larger.
class _WorstFrames extends StatelessWidget {
  const _WorstFrames({required this.stats, required this.fmtMicros});

  final FrameStatsSnapshot stats;
  final String Function(int?) fmtMicros;

  @override
  Widget build(BuildContext context) {
    final sorted = [...stats.recentFrames]
      ..sort((a, b) => b.totalMicros.compareTo(a.totalMicros));
    final worst = sorted.take(_kWorstFrameCount).toList();

    if (worst.isEmpty) {
      return Text('No worst-frame data.', style: RadarTypography.caption);
    }

    return Column(
      children: [
        for (final frame in worst)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _WorstFrameRow(frame: frame, fmtMicros: fmtMicros),
          ),
      ],
    );
  }
}

class _WorstFrameRow extends StatelessWidget {
  const _WorstFrameRow({required this.frame, required this.fmtMicros});

  final FrameSample frame;
  final String Function(int?) fmtMicros;

  @override
  Widget build(BuildContext context) {
    final isJank = frame.totalMicros > _kFrameBudgetMicros;
    final isCritical = frame.totalMicros > _kFrameCriticalMicros;
    final color = isCritical
        ? RadarColors.critical
        : isJank
        ? RadarColors.warning
        : RadarColors.text100;

    // Derives which phase dominated — this is computed from real data.
    final boundTag = frame.buildMicros >= frame.rasterMicros
        ? 'BUILD-BOUND'
        : 'RASTER-BOUND';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isJank ? color.withValues(alpha: 0.05) : RadarColors.bgSurface,
        borderRadius: RadarDensity.rowRadius,
        border: Border.all(
          color: isJank
              ? color.withValues(alpha: 0.20)
              : RadarColors.hairline08,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtMicros(frame.totalMicros),
                  style: RadarTypography.monoNumber.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(
                  'build ${fmtMicros(frame.buildMicros)} · '
                  'raster ${fmtMicros(frame.rasterMicros)}',
                  style: RadarTypography.monoLabel.copyWith(
                    color: RadarColors.text40,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          RadarTag(label: boundTag, color: color),
        ],
      ),
    );
  }
}
