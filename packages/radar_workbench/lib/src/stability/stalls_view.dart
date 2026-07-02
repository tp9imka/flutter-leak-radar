import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../perf/perf_data_controller.dart';
import '../perf/perf_snapshot_dto.dart';
import '../perf/perf_state_views.dart';

/// Stability ▸ Stalls — rows with duration colour-graded ≥1s red /
/// ≥600ms amber, proportional bar, and session-relative time.
class StallsView extends StatelessWidget {
  const StallsView({super.key, required this.controller});

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
          PerfLoadState.loaded => _buildLoaded(controller.snapshot!.stability),
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
            'Press Refresh to load stability data.',
            style: RadarTypography.body.copyWith(color: RadarColors.text40),
          ),
          const SizedBox(height: 12),
          PerfRefreshButton(onRefresh: controller.refresh),
        ],
      ),
    );
  }

  Widget _buildLoaded(StabilityDto stability) {
    final stalls = stability.recentStalls;
    final sessionStart = stalls.isNotEmpty ? stalls.last.clockMicros : 0;
    final maxDuration = stalls.fold(
      0,
      (m, s) => s.durationMicros > m ? s.durationMicros : m,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StallsToolbar(
          totalCount: stability.stallCount,
          onRefresh: controller.refresh,
        ),
        stalls.isEmpty
            ? const Expanded(
                child: Center(
                  child: Text(
                    'No stalls recorded.',
                    style: TextStyle(
                      fontFamily: 'HankenGrotesk',
                      fontSize: 13,
                      color: RadarColors.text40,
                    ),
                  ),
                ),
              )
            : Expanded(
                child: ListView.builder(
                  itemCount: stalls.length,
                  itemBuilder: (context, i) => _StallRow(
                    stall: stalls[i],
                    maxDurationMicros: maxDuration,
                    sessionStartMicros: sessionStart,
                  ),
                ),
              ),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _StallsToolbar extends StatelessWidget {
  const _StallsToolbar({required this.totalCount, required this.onRefresh});

  final int totalCount;
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
              'Stalls',
              style: RadarTypography.monoBody.copyWith(
                color: RadarColors.text80,
              ),
            ),
            const SizedBox(width: 8),
            if (totalCount > 0)
              RadarTag(label: '×$totalCount', color: RadarColors.warning),
            const Spacer(),
            PerfRefreshButton(onRefresh: onRefresh),
          ],
        ),
      ),
    );
  }
}

// ── Stall row ─────────────────────────────────────────────────────────────────

class _StallRow extends StatelessWidget {
  const _StallRow({
    required this.stall,
    required this.maxDurationMicros,
    required this.sessionStartMicros,
  });

  final StallRecordDto stall;
  final int maxDurationMicros;
  final int sessionStartMicros;

  static const _redThreshold = 1000000; // 1 s in µs
  static const _amberThreshold = 600000; // 600 ms in µs

  Color get _durationColor {
    if (stall.durationMicros >= _redThreshold) return RadarColors.critical;
    if (stall.durationMicros >= _amberThreshold) return RadarColors.warning;
    return RadarColors.text60;
  }

  static String _fmt(int us) {
    if (us < 1000) return '$usµs';
    if (us < 1000000) return '${(us / 1000).toStringAsFixed(0)}ms';
    return '${(us / 1000000).toStringAsFixed(2)}s';
  }

  static String _relativeTime(int clockMicros, int sessionStartMicros) {
    final delta = (clockMicros - sessionStartMicros).abs();
    final secs = delta ~/ 1000000;
    if (secs < 60) return '+${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '+${mins}m${rem.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final barFraction = maxDurationMicros > 0
        ? stall.durationMicros / maxDurationMicros
        : 0.0;

    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: RadarColors.hairline04,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.rowHPad,
          vertical: RadarDensity.rowVPad,
        ),
        child: Row(
          children: [
            // Colour-graded duration
            SizedBox(
              width: 70,
              child: Text(
                _fmt(stall.durationMicros),
                style: RadarTypography.monoNumber.copyWith(
                  color: _durationColor,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Proportional bar
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: constraints.maxWidth * barFraction,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _durationColor.withValues(alpha: 0.45),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            // Session-relative time
            SizedBox(
              width: 64,
              child: Text(
                _relativeTime(stall.clockMicros, sessionStartMicros),
                style: RadarTypography.monoLabel,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
