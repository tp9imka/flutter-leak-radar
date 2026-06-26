import 'package:flutter/material.dart';

import '../../model/stability_snapshot.dart';

/// Displays stability counters and recent error/stall events.
class StabilityPanel extends StatelessWidget {
  const StabilityPanel({super.key, required this.stability});

  final StabilitySnapshot stability;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard(
          title: 'Counters',
          children: [
            _Row(
              'Errors',
              '${stability.errorCount}',
              valueColor: stability.errorCount > 0
                  ? const Color(0xFFff5d6c)
                  : const Color(0xFF2fe39b),
            ),
            _Row(
              'Stalls',
              '${stability.stallCount}',
              valueColor: stability.stallCount > 0
                  ? const Color(0xFFf5b54a)
                  : const Color(0xFF2fe39b),
            ),
          ],
        ),
        if (stability.recentErrors.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _SectionHeader('Recent Errors'),
          ...stability.recentErrors.reversed.map(
            (e) => _EventTile(
              label: e.context ?? 'Error',
              detail: e.message,
              color: const Color(0xFFff5d6c),
            ),
          ),
        ],
        if (stability.recentStalls.isNotEmpty) ...[
          const SizedBox(height: 12),
          const _SectionHeader('Recent Stalls'),
          ...stability.recentStalls.reversed.map(
            (s) => _EventTile(
              label: 'Stall',
              detail: '${(s.durationMicros / 1000).toStringAsFixed(1)}ms',
              color: const Color(0xFFf5b54a),
            ),
          ),
        ],
        if (stability.recentErrors.isEmpty && stability.recentStalls.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                'No errors or stalls detected.',
                style: TextStyle(color: Color(0xFF7d8e94), fontSize: 13),
              ),
            ),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        letterSpacing: 0.8,
        color: Color(0xFF7d8e94),
      ),
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

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.label,
    required this.detail,
    required this.color,
  });

  final String label;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      border: Border.all(color: color.withValues(alpha: 0.25)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 4,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(
          '$label  ',
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: color),
        ),
        Expanded(
          child: Text(
            detail,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Color(0xFFa7b6bc),
            ),
          ),
        ),
      ],
    ),
  );
}
