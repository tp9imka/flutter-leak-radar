import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../perf/perf_data_controller.dart';
import '../perf/perf_snapshot_dto.dart';
import '../perf/perf_state_views.dart';

/// Stability ▸ Errors — table of recent errors with always-visible
/// stack-trace detail (no ExpansionTile).
///
/// Columns: message · type/context · last seen · count
class ErrorsView extends StatefulWidget {
  const ErrorsView({super.key, required this.controller});

  final PerfDataController controller;

  @override
  State<ErrorsView> createState() => _ErrorsViewState();
}

class _ErrorsViewState extends State<ErrorsView> {
  /// Index of the expanded stack-trace row, or null if none.
  int? _expandedIndex;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final state = widget.controller.loadState;
        return switch (state) {
          PerfLoadState.idle => _buildIdle(),
          PerfLoadState.loading => const PerfLoadingView(),
          PerfLoadState.notAvailable => const PerfRadarNotDetectedView(),
          PerfLoadState.error => PerfErrorView(
            message: widget.controller.errorMessage ?? 'Unknown error',
            onRetry: widget.controller.refresh,
          ),
          PerfLoadState.loaded => _buildLoaded(
            widget.controller.snapshot!.stability,
          ),
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
          PerfRefreshButton(onRefresh: widget.controller.refresh),
        ],
      ),
    );
  }

  Widget _buildLoaded(StabilityDto stability) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ErrorsToolbar(
          totalCount: stability.errorCount,
          onRefresh: widget.controller.refresh,
        ),
        _ErrorsHeader(),
        stability.recentErrors.isEmpty
            ? const Expanded(
                child: Center(
                  child: Text(
                    'No errors recorded.',
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
                  itemCount: stability.recentErrors.length,
                  itemBuilder: (context, i) {
                    final err = stability.recentErrors[i];
                    final isExpanded = _expandedIndex == i;
                    return _ErrorRow(
                      index: i,
                      sessionStartMicros: stability.recentErrors.isNotEmpty
                          ? stability.recentErrors.last.clockMicros
                          : 0,
                      error: err,
                      isExpanded: isExpanded,
                      onToggle: () => setState(
                        () => _expandedIndex = isExpanded ? null : i,
                      ),
                    );
                  },
                ),
              ),
      ],
    );
  }
}

// ── Toolbar ───────────────────────────────────────────────────────────────────

class _ErrorsToolbar extends StatelessWidget {
  const _ErrorsToolbar({required this.totalCount, required this.onRefresh});

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
              'Errors',
              style: RadarTypography.monoBody.copyWith(
                color: RadarColors.text80,
              ),
            ),
            const SizedBox(width: 8),
            if (totalCount > 0)
              RadarTag(label: '×$totalCount', color: RadarColors.critical),
            const Spacer(),
            PerfRefreshButton(onRefresh: onRefresh),
          ],
        ),
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _ErrorsHeader extends StatelessWidget {
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
        padding: const EdgeInsets.symmetric(
          horizontal: RadarDensity.rowHPad,
          vertical: 6,
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text('message', style: RadarTypography.monoLabel),
            ),
            Expanded(child: Text('type', style: RadarTypography.monoLabel)),
            SizedBox(
              width: 100,
              child: Text(
                'last seen',
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

// ── Row ───────────────────────────────────────────────────────────────────────

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    required this.index,
    required this.sessionStartMicros,
    required this.error,
    required this.isExpanded,
    required this.onToggle,
  });

  final int index;
  final int sessionStartMicros;
  final ErrorRecordDto error;
  final bool isExpanded;
  final VoidCallback onToggle;

  static String _relativeTime(int clockMicros, int sessionStartMicros) {
    // Display as session-relative time offset in seconds.
    final delta = (clockMicros - sessionStartMicros).abs();
    final secs = delta ~/ 1000000;
    if (secs < 60) return '+${secs}s';
    final mins = secs ~/ 60;
    final rem = secs % 60;
    return '+${mins}m${rem.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: const Border(
          bottom: BorderSide(
            color: RadarColors.hairline04,
            width: RadarDensity.hairline,
          ),
        ),
        color: isExpanded ? RadarColors.accentSubtle : Colors.transparent,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RadarDensity.rowHPad,
                vertical: RadarDensity.rowVPad,
              ),
              child: Row(
                children: [
                  // Expand toggle indicator
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 14,
                    color: RadarColors.text25,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    flex: 4,
                    child: Text(
                      error.message,
                      style: RadarTypography.monoBody.copyWith(
                        fontSize: 12,
                        color: RadarColors.critical,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error.context ?? '—',
                      style: RadarTypography.monoLabel.copyWith(
                        color: error.context != null
                            ? RadarColors.text60
                            : RadarColors.text15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 100,
                    child: Text(
                      _relativeTime(error.clockMicros, sessionStartMicros),
                      style: RadarTypography.monoLabel,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Always-visible detail block when expanded (NOT ExpansionTile)
          if (isExpanded) _StackTraceDetail(stackTrace: error.stackTraceString),
        ],
      ),
    );
  }
}

// ── Stack trace detail (always-visible, no ExpansionTile) ─────────────────────

class _StackTraceDetail extends StatelessWidget {
  const _StackTraceDetail({required this.stackTrace});

  final String? stackTrace;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RadarColors.bgCode,
        border: Border(
          top: BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(
          stackTrace ?? 'No stack trace recorded.',
          style: RadarTypography.monoCode.copyWith(
            color: stackTrace != null ? RadarColors.text80 : RadarColors.text25,
          ),
        ),
      ),
    );
  }
}
