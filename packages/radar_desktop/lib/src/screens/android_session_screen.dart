import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/native_profiling_controller.dart';

/// Android native-profiling session view: what's imported, the fidelity
/// state, quick totals, and entry points for the active workspace — the
/// section's entry point (see `docs/flutter_radar_android_profiling`
/// §4.1). Renders one of four states off [NativeProfilingController]:
/// loading, error, empty, or ready (fidelity banner + totals + imported
/// artifacts).
class AndroidSessionScreen extends StatelessWidget {
  const AndroidSessionScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.state == NativeImportState.loading) {
          return const _LoadingState();
        }
        if (controller.state == NativeImportState.error) {
          return _ErrorState(message: controller.errorMessage);
        }
        if (controller.checkpoints.isEmpty) {
          return const _EmptyState();
        }
        return _ReadyState(controller: controller);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No captures yet — import a .pftrace in Capture / import.',
        style: RadarTypography.caption,
        textAlign: TextAlign.center,
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
        Text('Analyzing trace…', style: RadarTypography.caption),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  /// Set by [NativeProfilingController] whenever `state` is `error`; only
  /// `null` if this widget is somehow built outside that invariant.
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          "Couldn't parse trace: ${message ?? 'unknown error'}",
          style: RadarTypography.caption.copyWith(color: RadarColors.critical),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState({required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    final checkpoints = controller.checkpoints;
    final growth = _growthMetric(checkpoints);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Session', style: RadarTypography.appBarTitle),
          const SizedBox(height: 12),
          RadarBanner(
            severity: controller.isSymbolized
                ? RadarSeverity.healthy
                : RadarSeverity.warning,
            message: controller.isSymbolized
                ? 'Fully symbolized'
                : 'Module-only — add a symbol store',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: RadarMetricTile(
                  label: 'Native still-live (latest)',
                  value: fmtBytes(checkpoints.last.totalStillLiveBytes),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RadarMetricTile(
                  label: 'Growth · first→latest',
                  value: growth.text,
                  color: growth.color,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: RadarMetricTile(
                  label: 'GPU total',
                  value: 'not reported · n/a on this device',
                  color: RadarColors.text25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Imported artifacts', style: RadarTypography.monoLabel),
          const SizedBox(height: 8),
          _ArtifactsList(controller: controller),
        ],
      ),
    );
  }
}

/// `first → latest` still-live growth, or a dimmed '—' when there is only
/// one checkpoint to measure from (matches the still-live table's own
/// null-delta convention in `android_native_module_row.dart`'s
/// `_DeltaText`).
({String text, Color color}) _growthMetric(
  List<NativeHeapProfile> checkpoints,
) {
  if (checkpoints.length < 2) {
    return (text: '—', color: RadarColors.text25);
  }
  final delta =
      checkpoints.last.totalStillLiveBytes -
      checkpoints.first.totalStillLiveBytes;
  final sign = delta > 0
      ? '+'
      : delta < 0
      ? '-'
      : '';
  final color = delta > 0
      ? RadarColors.critical
      : delta < 0
      ? RadarColors.accent
      : RadarColors.text40;
  return (text: '$sign${fmtBytes(delta.abs())}', color: color);
}

class _ArtifactsList extends StatelessWidget {
  const _ArtifactsList({required this.controller});

  final NativeProfilingController controller;

  @override
  Widget build(BuildContext context) {
    final rows = [
      for (final checkpoint in controller.checkpoints)
        _CheckpointRow(checkpoint: checkpoint),
      _PresenceRow(
        label: 'Symbol store',
        present: controller.symbolStore != null,
      ),
      _PresenceRow(label: 'ffi log', present: controller.ffiLog != null),
    ];

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
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1, color: RadarColors.hairline08),
            row,
          ],
        ],
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({required this.checkpoint});

  final NativeHeapProfile checkpoint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(
              checkpoint.label,
              style: RadarTypography.monoBody.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            fmtTime(checkpoint.capturedAt),
            style: RadarTypography.monoLabel,
          ),
          const SizedBox(width: 16),
          Text(
            fmtBytes(checkpoint.totalStillLiveBytes),
            style: RadarTypography.monoNumber.copyWith(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PresenceRow extends StatelessWidget {
  const _PresenceRow({required this.label, required this.present});

  final String label;
  final bool present;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(child: Text('$label:', style: RadarTypography.monoLabel)),
          RadarTag(
            label: present ? 'IMPORTED' : 'NONE',
            severity: present ? RadarSeverity.healthy : null,
          ),
        ],
      ),
    );
  }
}
