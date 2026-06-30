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
    return ExpansionTile(
      // Build hop children eagerly (kept offstage while collapsed) so the
      // path is ready to reveal instantly and is deterministically testable.
      maintainState: true,
      title: Text(
        title ?? 'Retaining path (${path.hops.length} hops)',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      subtitle: Text(
        'Root: ${path.rootKind.label}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      children: [
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
