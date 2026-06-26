import 'package:flutter/material.dart';

import '../../model/frame_stats.dart';

/// Displays frame timing percentiles and jank statistics.
class FrameStatsPanel extends StatelessWidget {
  const FrameStatsPanel({super.key, required this.stats});

  final FrameStatsSnapshot stats;

  String _fmt(int? micros) {
    if (micros == null) return '—';
    if (micros < 1000) return '$microsµs';
    return '${(micros / 1000).toStringAsFixed(1)}ms';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard(
          title: 'Frames',
          children: [
            _Row('Total frames', '${stats.frameCount}'),
            _Row(
              'Jank frames',
              '${stats.jankCount}',
              valueColor: stats.jankCount > 0
                  ? const Color(0xFFff5d6c)
                  : const Color(0xFF2fe39b),
            ),
            if (stats.frameCount > 0)
              _Row(
                'Jank rate',
                '${(stats.jankCount / stats.frameCount * 100).toStringAsFixed(1)}%',
              ),
          ],
        ),
        const SizedBox(height: 12),
        _MetricCard(
          title: 'Build Phase',
          children: [
            _Row('p50', _fmt(stats.buildP50)),
            _Row('p95', _fmt(stats.buildP95)),
            _Row('p99', _fmt(stats.buildP99)),
          ],
        ),
        const SizedBox(height: 12),
        _MetricCard(
          title: 'Raster Phase',
          children: [
            _Row('p50', _fmt(stats.rasterP50)),
            _Row('p95', _fmt(stats.rasterP95)),
            _Row('p99', _fmt(stats.rasterP99)),
          ],
        ),
        const SizedBox(height: 12),
        _MetricCard(
          title: 'Total Frame',
          children: [
            _Row('p50', _fmt(stats.totalP50)),
            _Row('p95', _fmt(stats.totalP95)),
            _Row('p99', _fmt(stats.totalP99)),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF0e1316),
      border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.08)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            letterSpacing: 0.8,
            color: Color(0xFF7d8e94),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFFa7b6bc),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: valueColor ?? const Color(0xFFe7eef0),
          ),
        ),
      ],
    ),
  );
}
