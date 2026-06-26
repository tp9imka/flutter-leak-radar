import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';

/// Displays per-label rebuild counts extracted from the [PerfRadar] snapshot.
///
/// Counts are derived from [TraceSnapshot.stats] by filtering keys whose
/// [TraceKey.name] starts with `'rebuild:'`. When no rebuild keys are present
/// the widget renders nothing (zero height).
class RebuildCountsPanel extends StatelessWidget {
  /// Creates a [RebuildCountsPanel] from [snapshot].
  const RebuildCountsPanel({super.key, required this.snapshot});

  /// The snapshot to filter rebuild spans from.
  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final entries =
        snapshot.stats.entries
            .where((e) => e.key.name.startsWith('rebuild:'))
            .toList()
          ..sort((a, b) => b.value.count.compareTo(a.value.count));

    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionHeader(),
        for (final e in entries)
          _RebuildRow(
            label: e.key.name.substring('rebuild:'.length),
            count: e.value.count,
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
    child: Text(
      'Rebuilds',
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF7d8e94),
        letterSpacing: 0.8,
      ),
    ),
  );
}

class _RebuildRow extends StatelessWidget {
  const _RebuildRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFF0e1316),
      border: Border.all(color: const Color.fromRGBO(47, 227, 155, 0.15)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: Color(0xFFe7eef0),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          '$count×',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2fe39b),
          ),
        ),
      ],
    ),
  );
}
