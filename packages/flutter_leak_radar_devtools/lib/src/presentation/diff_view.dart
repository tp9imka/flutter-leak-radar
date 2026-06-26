import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';

import '../diff/diff_controller.dart';

/// Ranked table of classes that grew between snapshot A and snapshot B.
class DiffView extends StatelessWidget {
  const DiffView({super.key, required this.controller});

  final DiffController controller;

  /// Returns only classes that actually grew (positive instance delta).
  List<ClassCountDiff> _positiveDeltas(List<ClassCountDiff> diff) =>
      diff.where((d) => d.instanceDelta > 0).toList();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final diff = controller.diff;
        if (diff == null) {
          return const Center(
            child: Text(
              'Capture A and B to see the diff.',
              textAlign: TextAlign.center,
            ),
          );
        }
        final grew = _positiveDeltas(diff);
        if (grew.isEmpty) {
          return const Center(
            child: Text('No classes grew between snapshots.'),
          );
        }
        return _DiffTable(grew: grew);
      },
    );
  }
}

class _DiffTable extends StatelessWidget {
  const _DiffTable({required this.grew});

  final List<ClassCountDiff> grew;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Class')),
          DataColumn(label: Text('Δ instances'), numeric: true),
          DataColumn(label: Text('Before'), numeric: true),
          DataColumn(label: Text('After'), numeric: true),
          DataColumn(label: Text('Δ bytes'), numeric: true),
        ],
        rows: [
          for (final d in grew)
            DataRow(
              cells: [
                DataCell(
                  Text(
                    d.after.className,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                DataCell(
                  Text(
                    '+${d.instanceDelta}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                DataCell(Text('${d.before.instanceCount}')),
                DataCell(Text('${d.after.instanceCount}')),
                DataCell(Text(_delta(d.bytesDelta))),
              ],
            ),
        ],
      ),
    );
  }

  String _delta(int bytes) {
    if (bytes == 0) return '0';
    final sign = bytes > 0 ? '+' : '';
    if (bytes.abs() < 1024) return '$sign$bytes B';
    if (bytes.abs() < 1024 * 1024) {
      return '$sign${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$sign${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
