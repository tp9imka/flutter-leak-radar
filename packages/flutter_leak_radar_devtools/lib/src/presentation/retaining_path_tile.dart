import 'package:flutter/material.dart';
import 'package:leak_graph/leak_graph.dart';

/// Displays a single [GraphRetainingPath] as an expandable tile.
class RetainingPathTile extends StatelessWidget {
  const RetainingPathTile({super.key, required this.path, this.title});

  final GraphRetainingPath path;
  final String? title;

  @override
  Widget build(BuildContext context) {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 12);
    // Rendered as an always-visible column rather than an ExpansionTile: the
    // retaining path is the key diagnostic and should be readable without a
    // tap, and this keeps the widget version-stable across Flutter releases.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title ?? 'Retaining path (${path.hops.length} hops)',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          'Root: ${path.rootKind.label}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < path.hops.length; i++)
          _HopRow(hop: path.hops[i], index: i, style: mono),
      ],
    );
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({required this.hop, required this.index, required this.style});

  final GraphHop hop;
  final int index;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final ref = hop.field != null
        ? '.${hop.field}'
        : hop.index != null
        ? '[${hop.index}]'
        : '';
    return Padding(
      padding: EdgeInsets.only(left: 16.0 + index * 8, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.arrow_downward, size: 12),
          const SizedBox(width: 4),
          Text('${hop.className}$ref', style: style),
        ],
      ),
    );
  }
}
