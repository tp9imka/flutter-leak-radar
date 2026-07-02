import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:radar_ui/radar_ui.dart';

import '../model/stall_record.dart';

/// Spans whose execution window overlaps [stall]'s blocking window
/// (`[clockMicros - durationMicros, clockMicros]`), slowest first.
///
/// Stalls and spans share the [traceClockNowMicros] clock, so the intervals are
/// directly comparable. Only spans retained as slowest-N exemplars are passed
/// in, so a fast-but-blocking operation may not appear — the caller is honest
/// about that in the UI rather than implying full coverage. Visible for testing.
@visibleForTesting
List<Span> spansOverlappingStall(StallRecord stall, Iterable<Span> spans) {
  final blockEnd = stall.clockMicros;
  final blockStart = stall.clockMicros - stall.durationMicros;
  final overlapping = [
    for (final s in spans)
      if (s.startMicros < blockEnd &&
          s.startMicros + s.durationMicros > blockStart)
        s,
  ]..sort((a, b) => b.durationMicros.compareTo(a.durationMicros));
  return overlapping;
}

/// Detail screen for a single main-thread [StallRecord].
///
/// Correlates the stall's blocking window with instrumented spans that were
/// running during it, turning an opaque "312ms stall" into "312ms stall
/// overlapped getConversationRecords (280ms)".
class StallDetailScreen extends StatelessWidget {
  const StallDetailScreen({
    super.key,
    required this.stall,
    this.candidateSpans = const [],
  });

  final StallRecord stall;

  /// Spans to correlate against — typically the retained slowest-N exemplars
  /// from the live trace snapshot.
  final List<Span> candidateSpans;

  static String _fmtMicros(int micros) {
    final ms = micros / 1000;
    if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)}s';
    return '${ms.toStringAsFixed(1)}ms';
  }

  static Color _durationColor(int micros) {
    if (micros >= 1000000) return RadarColors.critical;
    if (micros >= 600000) return RadarColors.warning;
    return RadarColors.text60;
  }

  @override
  Widget build(BuildContext context) {
    final overlapping = spansOverlappingStall(stall, candidateSpans);
    return Scaffold(
      backgroundColor: RadarColors.bgPhone,
      appBar: AppBar(
        backgroundColor: RadarColors.bgPanel,
        foregroundColor: RadarColors.text100,
        elevation: 0,
        title: Text('Stall detail', style: RadarTypography.appBarTitle),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: RadarColors.hairline08,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          16,
          12,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          _header(),
          const SizedBox(height: 16),
          Text(
            'Overlapping operations'
            '${overlapping.isEmpty ? '' : ' (${overlapping.length})'}',
            style: RadarTypography.monoLabel,
          ),
          const SizedBox(height: 6),
          if (overlapping.isEmpty)
            _emptyCorrelation()
          else
            for (final s in overlapping) _spanRow(s),
          const SizedBox(height: 12),
          _limitationNote(),
        ],
      ),
    );
  }

  Widget _header() {
    final color = _durationColor(stall.durationMicros);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.rowRadius,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _fmtMicros(stall.durationMicros),
                style: radarMonoStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'main-thread block',
                style: radarMonoStyle(fontSize: 12, color: RadarColors.text40),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'blocking window ≈ ${_fmtMicros(stall.durationMicros)} '
            'ending at t+${_fmtMicros(stall.clockMicros)}',
            style: radarMonoStyle(fontSize: 11, color: RadarColors.text60),
          ),
        ],
      ),
    );
  }

  Widget _spanRow(Span span) {
    final isError = span.status == SpanStatus.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.rowRadius,
        border: Border.all(color: RadarColors.hairline08),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              span.name,
              style: RadarTypography.monoBody.copyWith(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isError) ...[
            const RadarTag(label: 'ERR', color: RadarColors.critical),
            const SizedBox(width: 8),
          ],
          Text(
            _fmtMicros(span.durationMicros),
            style: radarMonoStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _durationColor(span.durationMicros),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCorrelation() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: RadarColors.bgSurface,
      borderRadius: RadarDensity.rowRadius,
      border: Border.all(color: RadarColors.hairline08),
    ),
    child: Text(
      'No instrumented span overlapped this stall — the blocking work '
      "wasn't traced.",
      style: radarMonoStyle(fontSize: 11.5, color: RadarColors.text40),
    ),
  );

  Widget _limitationNote() => Text(
    'Only the slowest retained spans are available to correlate; a '
    'fast-but-blocking operation may not appear here.',
    style: RadarTypography.caption,
  );
}
