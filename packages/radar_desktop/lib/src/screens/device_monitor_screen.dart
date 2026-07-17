import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

import 'device_monitor_controller.dart';
import 'live_memory_controller.dart';

/// The Device Monitor pane: import-first rendering of native session
/// timelines and radar_ci runs (chart + per-column verdicts + router summary +
/// batch-delta + session-vs-session compare), plus a connected-mode live tab
/// that polls the running app's Dart heap/external memory.
///
/// Import-first is the primary surface; the live tab is additive and only
/// active while connected.
class DeviceMonitorScreen extends StatefulWidget {
  /// Creates the pane over [controller] (import) and optional [live] (poll).
  const DeviceMonitorScreen({
    super.key,
    required this.controller,
    this.live,
    this.connected = false,
    this.onImportPrimary,
    this.onImportComparison,
  });

  /// The import-first controller.
  final DeviceMonitorController controller;

  /// The live-poll controller, or null when the pane is offline.
  final LiveMemoryController? live;

  /// Whether a live VM connection is available (gates the live tab).
  final bool connected;

  /// Opens a file picker for the primary artifact (wired by the shell).
  final VoidCallback? onImportPrimary;

  /// Opens a file picker for the comparison session (wired by the shell).
  final VoidCallback? onImportComparison;

  @override
  State<DeviceMonitorScreen> createState() => _DeviceMonitorScreenState();
}

class _DeviceMonitorScreenState extends State<DeviceMonitorScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabBar(
          index: _tab,
          liveEnabled: widget.connected && widget.live != null,
          onSelect: (i) => setState(() => _tab = i),
        ),
        Expanded(
          child: _tab == 0
              ? _ImportTab(
                  controller: widget.controller,
                  onImportPrimary: widget.onImportPrimary,
                  onImportComparison: widget.onImportComparison,
                )
              : _LiveTab(live: widget.live, connected: widget.connected),
        ),
      ],
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.index,
    required this.liveEnabled,
    required this.onSelect,
  });

  final int index;
  final bool liveEnabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      color: RadarColors.bgPage,
      child: Row(
        children: [
          _TabButton(
            label: 'Import',
            active: index == 0,
            onTap: () => onSelect(0),
          ),
          const SizedBox(width: 8),
          _TabButton(
            label: 'Live',
            active: index == 1,
            enabled: liveEnabled,
            onTap: liveEnabled ? () => onSelect(1) : null,
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? RadarColors.text15
        : active
        ? RadarColors.accent
        : RadarColors.text60;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? RadarColors.accentSubtle : null,
          borderRadius: RadarDensity.inputRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: RadarTypography.monoBody.copyWith(color: color)),
            if (!enabled) ...[
              const SizedBox(width: 6),
              Icon(Icons.lock_outline, size: 11, color: RadarColors.text15),
            ],
          ],
        ),
      ),
    );
  }
}

class _ImportTab extends StatelessWidget {
  const _ImportTab({
    required this.controller,
    required this.onImportPrimary,
    required this.onImportComparison,
  });

  final DeviceMonitorController controller;
  final VoidCallback? onImportPrimary;
  final VoidCallback? onImportComparison;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        switch (controller.state) {
          case MonitorState.idle:
            return _EmptyPrompt(onImport: onImportPrimary);
          case MonitorState.loading:
            return const _LoadingState();
          case MonitorState.error:
            return _ErrorPanel(
              message: controller.errorMessage,
              onImport: onImportPrimary,
            );
          case MonitorState.ready:
            return _AnalysisView(
              controller: controller,
              onImportPrimary: onImportPrimary,
              onImportComparison: onImportComparison,
            );
        }
      },
    );
  }
}

class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt({required this.onImport});

  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Import a native session (timeline.json) or a radar_ci run.json '
              'to see its memory trend and verdict.',
              style: RadarTypography.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onImport, child: const Text('Import file')),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const RadarLinearProgress(),
        const SizedBox(height: 12),
        Text('Reading artifact…', style: RadarTypography.caption),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onImport});

  final String? message;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RadarBanner(
              severity: RadarSeverity.critical,
              message: "Couldn't import: ${message ?? 'unknown error'}",
            ),
            const SizedBox(height: 16),
            Center(
              child: OutlinedButton(
                onPressed: onImport,
                child: const Text('Try another file'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisView extends StatelessWidget {
  const _AnalysisView({
    required this.controller,
    required this.onImportPrimary,
    required this.onImportComparison,
  });

  final DeviceMonitorController controller;
  final VoidCallback? onImportPrimary;
  final VoidCallback? onImportComparison;

  @override
  Widget build(BuildContext context) {
    final analysis = controller.primary!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(analysis: analysis, onImport: onImportPrimary),
          const SizedBox(height: 12),
          RadarBanner(
            severity: _summarySeverity(analysis),
            message: analysis.summary,
          ),
          const SizedBox(height: 18),
          _MonitorChart(analysis: analysis),
          const SizedBox(height: 18),
          Text('Per-column verdicts', style: RadarTypography.monoLabel),
          const SizedBox(height: 8),
          _VerdictChips(series: analysis.series),
          const SizedBox(height: 18),
          _BatchDeltaReadout(series: analysis.series),
          if (analysis.session != null) ...[
            const SizedBox(height: 20),
            _CompareSection(
              controller: controller,
              onImportComparison: onImportComparison,
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.analysis, required this.onImport});

  final MonitorAnalysis analysis;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final provenance = analysis.provenance?.line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                analysis.label,
                style: RadarTypography.appBarTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            RadarTag(
              label: analysis.kind == MonitorSourceKind.session
                  ? 'SESSION'
                  : 'CI RUN',
              severity: RadarSeverity.info,
            ),
            const Spacer(),
            OutlinedButton(onPressed: onImport, child: const Text('Import…')),
          ],
        ),
        if (provenance != null) ...[
          const SizedBox(height: 6),
          Text(provenance, style: RadarTypography.monoLabel),
        ],
      ],
    );
  }
}

class _MonitorChart extends StatelessWidget {
  const _MonitorChart({required this.analysis});

  final MonitorAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final window = analysis.settleWindow;
    return RadarTimeSeriesChart(
      series: [
        for (final (i, m) in analysis.series.indexed)
          ChartSeries(
            label: m.label,
            color: _paletteAt(i),
            points: [
              for (final s in m.series.samples)
                (tMicros: s.tMicros, value: s.value),
            ],
            gaps: [
              for (final g in m.series.gaps)
                (startMicros: g.startMicros, endMicros: g.endMicros),
            ],
          ),
      ],
      marks: [
        for (final mk in analysis.marks)
          ChartMark(tMicros: mk.tMicros, label: mk.label),
      ],
      shaded: window == null
          ? const []
          : [
              ChartWindow(
                startMicros: window.startMicros,
                endMicros: window.endMicros,
              ),
            ],
      // Series span multiple units (kb / count / bytes); normalize each to its
      // own range so they overlay honestly on one time axis.
      normalizePerSeries: true,
    );
  }
}

class _VerdictChips extends StatelessWidget {
  const _VerdictChips({required this.series});

  final List<MonitorSeries> series;

  @override
  Widget build(BuildContext context) {
    if (series.isEmpty) {
      return Text(
        'No measured series in this artifact.',
        style: RadarTypography.monoLabel,
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [for (final s in series) _VerdictChip(series: s)],
    );
  }
}

class _VerdictChip extends StatelessWidget {
  const _VerdictChip({required this.series});

  final MonitorSeries series;

  @override
  Widget build(BuildContext context) {
    final verdict = series.assessment.verdict;
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              series.label,
              style: RadarTypography.monoBody.copyWith(fontSize: 12),
            ),
            const SizedBox(width: 8),
            RadarTag(
              label: _verdictTag(verdict),
              severity: _verdictSeverity(verdict),
            ),
            const SizedBox(width: 8),
            Text(
              _slopeLabel(series),
              style: RadarTypography.monoNumber.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchDeltaReadout extends StatelessWidget {
  const _BatchDeltaReadout({required this.series});

  final List<MonitorSeries> series;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Batch delta · init-free growth signal',
          style: RadarTypography.monoLabel,
        ),
        const SizedBox(height: 8),
        for (final s in series)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.label,
                    style: RadarTypography.monoLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _batchDeltaLabel(s),
                  style: RadarTypography.monoNumber.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CompareSection extends StatelessWidget {
  const _CompareSection({
    required this.controller,
    required this.onImportComparison,
  });

  final DeviceMonitorController controller;
  final VoidCallback? onImportComparison;

  @override
  Widget build(BuildContext context) {
    final columns = controller.compareColumnsList;
    final error = controller.comparisonError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Compare with a session', style: RadarTypography.monoLabel),
            const Spacer(),
            OutlinedButton(
              onPressed: onImportComparison,
              child: Text(columns == null ? 'Add second session…' : 'Replace…'),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          RadarBanner(severity: RadarSeverity.warning, message: error),
        ],
        if (columns != null) ...[
          const SizedBox(height: 12),
          _CompareTable(
            before: controller.primary!,
            after: controller.comparison!,
            columns: columns,
          ),
        ],
      ],
    );
  }
}

class _CompareTable extends StatelessWidget {
  const _CompareTable({
    required this.before,
    required this.after,
    required this.columns,
  });

  final MonitorAnalysis before;
  final MonitorAnalysis after;
  final List<ColumnComparison> columns;

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
      child: Column(
        children: [
          _CompareHeader(beforeLabel: before.label, afterLabel: after.label),
          for (final (i, c) in columns.indexed) ...[
            const Divider(height: 1, color: RadarColors.hairline08),
            _CompareRow(comparison: c, striped: i.isOdd),
          ],
        ],
      ),
    );
  }
}

class _CompareHeader extends StatelessWidget {
  const _CompareHeader({required this.beforeLabel, required this.afterLabel});

  final String beforeLabel;
  final String afterLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text('column', style: RadarTypography.monoLabel),
          ),
          Expanded(
            flex: 3,
            child: Text(
              beforeLabel,
              style: RadarTypography.monoLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              afterLabel,
              style: RadarTypography.monoLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('outcome', style: RadarTypography.monoLabel),
          ),
        ],
      ),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.comparison, required this.striped});

  final ColumnComparison comparison;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: striped ? RadarColors.rowBgDefault : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              comparison.column.name,
              style: RadarTypography.monoBody.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 3, child: _sideText(comparison.before)),
          Expanded(flex: 3, child: _sideText(comparison.after)),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: RadarTag(
                label: comparison.transition.name.toUpperCase(),
                severity: _transitionSeverity(comparison.transition),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideText(SeriesAssessment? assessment) {
    if (assessment == null) {
      return Text(
        'not measured',
        style: RadarTypography.monoLabel.copyWith(color: RadarColors.text25),
        overflow: TextOverflow.ellipsis,
      );
    }
    final slope = assessment.slopePerHour;
    final slopeText = slope == null ? '' : ' · ${_signed(slope)}/h';
    return Text(
      '${_verdictTag(assessment.verdict).toLowerCase()}$slopeText',
      style: RadarTypography.monoBody.copyWith(fontSize: 11),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _LiveTab extends StatelessWidget {
  const _LiveTab({required this.live, required this.connected});

  final LiveMemoryController? live;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final controller = live;
    if (!connected || controller == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Connect to a running app to poll live Dart heap and external '
            'memory.',
            style: RadarTypography.caption,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final heap = controller.heapSeries;
        final external = controller.externalSeries;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const RadarLivePulseDot(),
                  const SizedBox(width: 8),
                  Text(
                    'Live memory · ${controller.sampleCount} samples',
                    style: RadarTypography.appBarTitle,
                  ),
                ],
              ),
              if (controller.lastError != null) ...[
                const SizedBox(height: 12),
                RadarBanner(
                  severity: RadarSeverity.warning,
                  message: 'Polling paused — ${controller.lastError}',
                ),
              ],
              const SizedBox(height: 16),
              RadarTimeSeriesChart(
                series: [
                  ChartSeries(
                    label: 'heap',
                    color: RadarColors.accent,
                    points: [
                      for (final s in heap.samples)
                        (tMicros: s.tMicros, value: s.value),
                    ],
                    gaps: [
                      for (final g in heap.gaps)
                        (startMicros: g.startMicros, endMicros: g.endMicros),
                    ],
                  ),
                  ChartSeries(
                    label: 'external',
                    color: RadarColors.info,
                    points: [
                      for (final s in external.samples)
                        (tMicros: s.tMicros, value: s.value),
                    ],
                    gaps: [
                      for (final g in external.gaps)
                        (startMicros: g.startMicros, endMicros: g.endMicros),
                    ],
                  ),
                ],
                normalizePerSeries: true,
              ),
              const SizedBox(height: 10),
              Text(
                'Heap and external are tracked separately — external memory '
                'applies GC pressure but is not part of the Dart heap.',
                style: RadarTypography.monoLabel,
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- shared presentation helpers ---------------------------------------------

const List<Color> _palette = [
  RadarColors.accent,
  RadarColors.info,
  RadarColors.warning,
  RadarColors.violet,
  RadarColors.critical,
  RadarColors.text60,
];

Color _paletteAt(int i) => _palette[i % _palette.length];

String _verdictTag(SeriesVerdict verdict) => switch (verdict) {
  SeriesVerdict.monotonicGrowth => 'GROWTH',
  SeriesVerdict.plateau => 'PLATEAU',
  SeriesVerdict.noisy => 'NOISY',
  SeriesVerdict.insufficientData => 'NO DATA',
};

RadarSeverity _verdictSeverity(SeriesVerdict verdict) => switch (verdict) {
  SeriesVerdict.monotonicGrowth => RadarSeverity.critical,
  SeriesVerdict.plateau => RadarSeverity.healthy,
  SeriesVerdict.noisy => RadarSeverity.warning,
  SeriesVerdict.insufficientData => RadarSeverity.info,
};

RadarSeverity _bucketSeverity(TriageBucket? bucket) {
  if (bucket == null) return RadarSeverity.info;
  return bucket == TriageBucket.none
      ? RadarSeverity.healthy
      : RadarSeverity.critical;
}

/// The summary banner severity: an early-ended (aborted) run is thinner
/// evidence and is emphasised as a warning, otherwise the bucket drives it.
RadarSeverity _summarySeverity(MonitorAnalysis analysis) =>
    analysis.aborted ? RadarSeverity.warning : _bucketSeverity(analysis.bucket);

RadarSeverity _transitionSeverity(FixTransition t) => switch (t) {
  FixTransition.resolved => RadarSeverity.healthy,
  FixTransition.persists ||
  FixTransition.regressed ||
  FixTransition.newlyGrowing => RadarSeverity.critical,
  FixTransition.inconclusive ||
  FixTransition.measuredBeforeOnly ||
  FixTransition.measuredAfterOnly => RadarSeverity.warning,
  FixTransition.stable || FixTransition.notMeasured => RadarSeverity.info,
};

String _slopeLabel(MonitorSeries series) {
  final slope = series.assessment.slopePerHour;
  if (slope == null) return '—';
  return '${_signed(slope)} ${series.series.unit}/h';
}

String _batchDeltaLabel(MonitorSeries series) {
  final delta = series.assessment.batchDeltaPerHour;
  if (delta == null) return 'n/a';
  return '${_signed(delta)} ${series.series.unit}/h';
}

/// A signed, magnitude-scaled rate string (mirrors the triage renderer's
/// readability rule).
String _signed(double value) {
  final magnitude = value.abs();
  final String text;
  if (magnitude >= 100) {
    text = value.toStringAsFixed(0);
  } else if (magnitude >= 10) {
    text = value.toStringAsFixed(1);
  } else {
    text = value.toStringAsFixed(2);
  }
  return value >= 0 ? '+$text' : text;
}
