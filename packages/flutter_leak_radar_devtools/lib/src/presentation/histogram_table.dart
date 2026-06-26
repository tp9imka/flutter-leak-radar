import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';

/// Sortable, filterable table of per-class instance counts.
///
/// Shows all classes from a snapshot's [ClassCount] histogram.
class HistogramTable extends StatefulWidget {
  const HistogramTable({super.key, required this.histogram});

  final List<ClassCount> histogram;

  @override
  State<HistogramTable> createState() => _HistogramTableState();
}

class _HistogramTableState extends State<HistogramTable> {
  int _sortColumnIndex = 1; // default: sort by instanceCount
  bool _sortAscending = false;
  String _filter = '';

  List<ClassCount> get _sorted {
    final filtered = widget.histogram.where((c) {
      if (_filter.isEmpty) return true;
      return c.className.toLowerCase().contains(_filter.toLowerCase());
    }).toList();
    filtered.sort((a, b) {
      final cmp = switch (_sortColumnIndex) {
        0 => a.className.compareTo(b.className),
        1 => a.instanceCount.compareTo(b.instanceCount),
        _ => a.shallowBytes.compareTo(b.shallowBytes),
      };
      return _sortAscending ? cmp : -cmp;
    });
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.histogram.isEmpty) {
      return const Center(child: Text('No snapshot captured yet.'));
    }
    final rows = _sorted;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Filter by class name…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: DataTable(
              sortColumnIndex: _sortColumnIndex,
              sortAscending: _sortAscending,
              columns: [
                DataColumn(
                  label: const Text('Class'),
                  onSort: (i, asc) => setState(() {
                    _sortColumnIndex = i;
                    _sortAscending = asc;
                  }),
                ),
                DataColumn(
                  label: const Text('Instances'),
                  numeric: true,
                  onSort: (i, asc) => setState(() {
                    _sortColumnIndex = i;
                    _sortAscending = asc;
                  }),
                ),
                DataColumn(
                  label: const Text('Shallow bytes'),
                  numeric: true,
                  onSort: (i, asc) => setState(() {
                    _sortColumnIndex = i;
                    _sortAscending = asc;
                  }),
                ),
              ],
              rows: [
                for (final c in rows)
                  DataRow(
                    cells: [
                      DataCell(
                        Text(
                          c.className,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ),
                      DataCell(Text('${c.instanceCount}')),
                      DataCell(Text(_formatBytes(c.shallowBytes))),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
