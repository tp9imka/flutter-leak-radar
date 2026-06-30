import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import 'perf_data_controller.dart';
import 'perf_snapshot_dto.dart';
import 'perf_state_views.dart';

/// Performance ▸ Frames — jank stats + frame-time bar timeline +
/// build/raster percentiles + worst frames list.
class FramesView extends StatelessWidget {
  const FramesView({super.key, required this.controller});

  final PerfDataController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.loadState;
        return switch (state) {
          PerfLoadState.idle => _buildIdle(),
          PerfLoadState.loading => const PerfLoadingView(),
          PerfLoadState.notAvailable => const PerfRadarNotDetectedView(),
          PerfLoadState.error => PerfErrorView(
            message: controller.errorMessage ?? 'Unknown error',
            onRetry: controller.refresh,
          ),
          PerfLoadState.loaded => _buildLoaded(controller.snapshot!.frames),
        };
      },
    );
  }

  Widget _buildIdle() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Press Refresh to load frame data.',
            style: RadarTypography.body.copyWith(color: RadarColors.text40),
          ),
          const SizedBox(height: 12),
          PerfRefreshButton(onRefresh: controller.refresh),
        ],
      ),
    );
  }

  Widget _buildLoaded(FramesDto frames) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FramesToolbar(onRefresh: controller.refresh),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _StatTilesRow(frames: frames),
                const SizedBox(height: 16),
                _PercentilesSection(frames: frames),
                const SizedBox(height: 16),
                _FrameTimeline(frames: frames.recentFrames),
                if (frames.recentFrames.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _WorstFrames(frames: frames.recentFrames),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _FramesToolbar extends StatelessWidget {
  const _FramesToolbar({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.bgTableHeader,
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Text(
              'Frames',
              style: RadarTypography.monoBody.copyWith(
                color: RadarColors.text80,
              ),
            ),
            const Spacer(),
            PerfRefreshButton(onRefresh: onRefresh),
          ],
        ),
      ),
    );
  }
}

// ── Stat tiles ─────────────────────────────────────────────────────────────────

class _StatTilesRow extends StatelessWidget {
  const _StatTilesRow({required this.frames});

  final FramesDto frames;

  static String _pct(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final jankPct = frames.jankPercent;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        RadarMetricTile(
          label: 'Total frames',
          value: frames.frameCount.toString(),
        ),
        RadarMetricTile(
          label: 'Jank frames',
          value: frames.jankCount.toString(),
          severity: frames.jankCount > 0 ? RadarSeverity.warning : null,
        ),
        RadarMetricTile(
          label: 'Jank %',
          value: _pct(jankPct),
          severity: (jankPct ?? 0) > 5 ? RadarSeverity.critical : null,
        ),
      ],
    );
  }
}

// ── Percentiles section ───────────────────────────────────────────────────────

class _PercentilesSection extends StatelessWidget {
  const _PercentilesSection({required this.frames});

  final FramesDto frames;

  static String _us(int? v) => v == null ? '—' : _formatMicros(v);

  static String _formatMicros(int us) {
    if (us < 1000) return '$usµs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)}ms';
    return '${(us / 1000000).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PERCENTILES',
              style: RadarTypography.monoLabel.copyWith(
                letterSpacing: 0.08 * 10,
              ),
            ),
            const SizedBox(height: 10),
            _PercRow(
              label: 'Build',
              p50: _us(frames.buildP50),
              p95: _us(frames.buildP95),
              p99: _us(frames.buildP99),
            ),
            const SizedBox(height: 6),
            _PercRow(
              label: 'Raster',
              p50: _us(frames.rasterP50),
              p95: _us(frames.rasterP95),
              p99: _us(frames.rasterP99),
            ),
            const SizedBox(height: 6),
            _PercRow(
              label: 'Total',
              p50: _us(frames.totalP50),
              p95: _us(frames.totalP95),
              p99: _us(frames.totalP99),
            ),
          ],
        ),
      ),
    );
  }
}

class _PercRow extends StatelessWidget {
  const _PercRow({
    required this.label,
    required this.p50,
    required this.p95,
    required this.p99,
  });

  final String label;
  final String p50;
  final String p95;
  final String p99;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: RadarTypography.monoLabel),
        ),
        _Cell('p50', p50),
        _Cell('p95', p95),
        _Cell('p99', p99),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.text25,
            ),
          ),
          Text(
            value,
            style: RadarTypography.monoNumber.copyWith(
              fontSize: 12,
              color: value == '—' ? RadarColors.text15 : RadarColors.text80,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Frame timeline ────────────────────────────────────────────────────────────

/// Bar chart of recent frames; over-budget bars are amber/red.
class _FrameTimeline extends StatelessWidget {
  const _FrameTimeline({required this.frames});

  final List<RecentFrameDto> frames;

  static const _budget = 16666; // 60 fps in µs
  static const _barWidth = 4.0;
  static const _maxHeight = 64.0;

  @override
  Widget build(BuildContext context) {
    if (frames.isEmpty) {
      return _empty();
    }

    final maxTotal = frames.fold(
      0,
      (m, f) => f.totalMicros > m ? f.totalMicros : m,
    );
    final scale = maxTotal > 0 ? _maxHeight / maxTotal : 1.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RECENT FRAMES',
              style: RadarTypography.monoLabel.copyWith(
                letterSpacing: 0.08 * 10,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _maxHeight + 4,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final f in frames)
                      _FrameBar(
                        frame: f,
                        height: (f.totalMicros * scale).clamp(1.0, _maxHeight),
                        isJank: f.totalMicros > _budget,
                        width: _barWidth,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _Legend(color: RadarColors.accent, label: '≤16 ms'),
                const SizedBox(width: 12),
                _Legend(color: RadarColors.warning, label: 'jank'),
                const SizedBox(width: 12),
                _Legend(color: RadarColors.critical, label: '>2× budget'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No frame data recorded yet.',
          style: RadarTypography.caption,
        ),
      ),
    );
  }
}

class _FrameBar extends StatelessWidget {
  const _FrameBar({
    required this.frame,
    required this.height,
    required this.isJank,
    required this.width,
  });

  final RecentFrameDto frame;
  final double height;
  final bool isJank;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Color color;
    if (frame.totalMicros > 33333) {
      color = RadarColors.critical;
    } else if (isJank) {
      color = RadarColors.warning;
    } else {
      color = RadarColors.accent;
    }

    return Tooltip(
      message:
          'total: ${_fmt(frame.totalMicros)}\n'
          'build: ${_fmt(frame.buildMicros)}\n'
          'raster: ${_fmt(frame.rasterMicros)}',
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        color: color,
      ),
    );
  }

  static String _fmt(int us) {
    if (us < 1000) return '$usµs';
    return '${(us / 1000).toStringAsFixed(1)}ms';
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 4),
        Text(label, style: RadarTypography.caption),
      ],
    );
  }
}

// ── Worst frames ──────────────────────────────────────────────────────────────

class _WorstFrames extends StatelessWidget {
  const _WorstFrames({required this.frames});

  final List<RecentFrameDto> frames;

  static const _topN = 5;

  static String _fmt(int us) {
    if (us < 1000) return '$usµs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(1)}ms';
    return '${(us / 1000000).toStringAsFixed(2)}s';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List.of(frames)
      ..sort((a, b) => b.totalMicros.compareTo(a.totalMicros));
    final top = sorted.take(_topN).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WORST FRAMES (TOP $topN)',
              style: RadarTypography.monoLabel.copyWith(
                letterSpacing: 0.08 * 10,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < top.length; i++)
              _WorstFrameRow(rank: i + 1, frame: top[i], fmt: _fmt),
          ],
        ),
      ),
    );
  }

  static const topN = _topN;
}

class _WorstFrameRow extends StatelessWidget {
  const _WorstFrameRow({
    required this.rank,
    required this.frame,
    required this.fmt,
  });

  final int rank;
  final RecentFrameDto frame;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '#$rank',
              style: RadarTypography.monoLabel.copyWith(
                color: RadarColors.text25,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _Val('total', fmt(frame.totalMicros)),
          const SizedBox(width: 16),
          _Val('build', fmt(frame.buildMicros)),
          const SizedBox(width: 16),
          _Val('raster', fmt(frame.rasterMicros)),
        ],
      ),
    );
  }
}

class _Val extends StatelessWidget {
  const _Val(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label ',
          style: RadarTypography.caption.copyWith(color: RadarColors.text25),
        ),
        Text(value, style: RadarTypography.monoNumber.copyWith(fontSize: 12)),
      ],
    );
  }
}
