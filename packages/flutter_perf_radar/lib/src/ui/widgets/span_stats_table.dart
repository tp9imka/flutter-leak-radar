// Copyright (c) 2025, tp9imka. All rights reserved.

import 'package:flutter/material.dart';
import 'package:radar_trace/radar_trace.dart';

/// Renders a sorted list of [SpanKeyStatsSnapshot] entries from [snapshot].
class SpanStatsTable extends StatelessWidget {
  const SpanStatsTable({super.key, required this.snapshot});

  final TraceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final entries = snapshot.stats.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));

    if (entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No spans recorded yet.\nUse PerfRadar.trace() to instrument code.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFa7b6bc), fontSize: 13),
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemBuilder: (context, i) => _SpanRow(stats: entries[i]),
    );
  }
}

class _SpanRow extends StatelessWidget {
  const _SpanRow({required this.stats});

  final SpanKeyStatsSnapshot stats;

  String _fmt(int? micros) => micros == null ? '—' : '$microsµs';

  @override
  Widget build(BuildContext context) {
    final hist = stats.histogram;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0e1316),
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  stats.key.name,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFe7eef0),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${stats.count}×',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF2fe39b),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _Metric('p50', _fmt(hist.percentile(0.50))),
              const SizedBox(width: 16),
              _Metric('p95', _fmt(hist.percentile(0.95))),
              const SizedBox(width: 16),
              _Metric('p99', _fmt(hist.percentile(0.99))),
              if (stats.errorCount > 0) ...[
                const SizedBox(width: 16),
                _Metric(
                  'err',
                  '${stats.errorCount}',
                  color: const Color(0xFFff5d6c),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, {this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$label ',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: Color(0xFF7d8e94),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: color ?? const Color(0xFFcdd6da),
        ),
      ),
    ],
  );
}
