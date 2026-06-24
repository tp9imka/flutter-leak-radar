import 'package:flutter/material.dart';

import '../model/retaining_path.dart';

/// Expansion tile that lazily fetches and renders a retaining path.
///
/// [onFetch] is called at most once (on first expand). Subsequent expands
/// reuse the cached result. A null return renders "unavailable".
class RetainingPathTile extends StatefulWidget {
  const RetainingPathTile({
    super.key,
    required this.className,
    required this.onFetch,
  });

  /// The class name shown in the tile header.
  final String className;

  /// Invoked once on first expand to obtain the retaining path.
  ///
  /// Must never throw — callers are expected to wrap in try/catch before
  /// passing here. A null result renders the "unavailable" message.
  final Future<RetainingPathView?> Function() onFetch;

  @override
  State<RetainingPathTile> createState() => _RetainingPathTileState();
}

class _RetainingPathTileState extends State<RetainingPathTile> {
  bool _fetching = false;
  bool _fetched = false;
  RetainingPathView? _path;

  Future<void> _fetch() async {
    if (_fetched || _fetching) return;
    setState(() => _fetching = true);
    final path = await widget.onFetch();
    if (!mounted) return;
    setState(() {
      _fetching = false;
      _fetched = true;
      _path = path;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text('Retaining path — ${widget.className}'),
      onExpansionChanged: (expanded) {
        if (expanded) _fetch();
      },
      children: [_body()],
    );
  }

  Widget _body() {
    if (_fetching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (!_fetched) return const SizedBox.shrink();
    final path = _path;
    if (path == null) {
      return const ListTile(
        dense: true,
        title: Text('Retaining path unavailable'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (path.gcRootType != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.anchor, size: 16),
            title: Text('GC root: ${path.gcRootType}'),
          ),
        for (final hop in path.elements) _HopTile(hop: hop),
      ],
    );
  }
}

class _HopTile extends StatelessWidget {
  const _HopTile({required this.hop});

  final RetainingHop hop;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[hop.objectType];
    if (hop.field != null) parts.add('.${hop.field}');
    if (hop.index != null) parts.add('[${hop.index}]');
    if (hop.mapKey != null) parts.add('["${hop.mapKey}"]');
    return ListTile(
      dense: true,
      leading: const Icon(Icons.arrow_downward, size: 14),
      title: Text(parts.join()),
    );
  }
}
