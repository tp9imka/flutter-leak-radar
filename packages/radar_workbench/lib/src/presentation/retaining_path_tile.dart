import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';

import '../memory/mem_format.dart';

/// The `.field` / `[index]` accessor a hop holds the next object by, or `''`.
String _hopRef(GraphHop hop) {
  if (hop.field != null) return '.${hop.field}';
  if (hop.index != null) return '[${hop.index}]';
  return '';
}

/// `ClassName.field` / `ClassName[index]` label for a single hop.
String hopLabel(GraphHop hop) => '${hop.className}${_hopRef(hop)}';

/// A copyable, plain-text rendering of [path]: a root line, then one line per
/// hop with its accessor and (when known) declaring library uri.
///
/// [anchorHopIndex] marks the hop app code holds the leak at with a trailing
/// `<- yours` so a pasted path still shows where "your" code sits. This is the
/// text the tile's copy button places on the clipboard.
String retainingPathText(GraphRetainingPath path, {int? anchorHopIndex}) {
  final buffer = StringBuffer('Root: ${path.rootKind.label}');
  for (var i = 0; i < path.hops.length; i++) {
    final hop = path.hops[i];
    buffer.write('\n');
    if (i > 0) buffer.write('> ');
    buffer.write(hopLabel(hop));
    if (hop.libraryUri != null) buffer.write('  (${hop.libraryUri})');
    if (i == anchorHopIndex) buffer.write('  <- yours');
  }
  return buffer.toString();
}

/// Displays a single [GraphRetainingPath] as an always-visible hop column.
///
/// Each hop carries a colored left tick and an [OriginChip] derived from its
/// declaring library ([projectPackages] resolves what counts as "yours"). The
/// anchor hop ([anchorHopIndex]) — the one app code holds the leak at — is
/// highlighted with a "yours" marker. Hop text is selectable, a copy button
/// yields [retainingPathText], and, when [onOpenSource] is provided (desktop),
/// package-uri hops gain an open-in-editor affordance.
class RetainingPathTile extends StatelessWidget {
  const RetainingPathTile({
    super.key,
    required this.path,
    this.title,
    this.anchorHopIndex,
    this.projectPackages = const {},
    this.onOpenSource,
  });

  final GraphRetainingPath path;
  final String? title;

  /// Index into [path] `.hops` of the "yours" anchor, or null when this path
  /// has no known anchor (rendered without a highlight — never guessed).
  final int? anchorHopIndex;

  /// Resolved project package names, classifying each hop's origin.
  final Set<String> projectPackages;

  /// Opens a hop's declaring library in an editor; null disables the affordance
  /// (DevTools / copy-only). Returns whether it launched.
  final Future<bool> Function(Uri libraryUri)? onOpenSource;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title ?? 'Retaining path (${path.hops.length} hops)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            _CopyPathButton(
              text: () =>
                  retainingPathText(path, anchorHopIndex: anchorHopIndex),
            ),
          ],
        ),
        Text(
          'Root: ${path.rootKind.label}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < path.hops.length; i++)
          _HopRow(
            hop: path.hops[i],
            index: i,
            isAnchor: i == anchorHopIndex,
            projectPackages: projectPackages,
            onOpenSource: onOpenSource,
          ),
      ],
    );
  }
}

class _CopyPathButton extends StatelessWidget {
  const _CopyPathButton({required this.text});

  final String Function() text;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.copy, size: 14),
      tooltip: 'Copy path',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      color: RadarColors.text60,
      onPressed: () => Clipboard.setData(ClipboardData(text: text())),
    );
  }
}

class _HopRow extends StatelessWidget {
  const _HopRow({
    required this.hop,
    required this.index,
    required this.isAnchor,
    required this.projectPackages,
    required this.onOpenSource,
  });

  final GraphHop hop;
  final int index;
  final bool isAnchor;
  final Set<String> projectPackages;
  final Future<bool> Function(Uri libraryUri)? onOpenSource;

  static const _mono = TextStyle(fontFamily: 'monospace', fontSize: 12);

  bool get _canOpen =>
      onOpenSource != null &&
      hop.libraryUri != null &&
      hop.libraryUri!.scheme == 'package';

  @override
  Widget build(BuildContext context) {
    final origin = originOf(hop.libraryUri, projectPackages: projectPackages);
    final tickColor = isAnchor ? RadarColors.violet : origin.color;
    // Cap indent growth so deep paths stay inside the narrow detail panel.
    final indent = 16.0 + (index < 8 ? index : 8) * 6;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.only(left: indent),
      decoration: isAnchor
          ? BoxDecoration(
              color: RadarColors.violet.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.all(Radius.circular(4)),
            )
          : null,
      child: Row(
        children: [
          Container(width: 3, height: 16, color: tickColor),
          const SizedBox(width: 6),
          Expanded(child: SelectableText(hopLabel(hop), style: _mono)),
          if (isAnchor)
            const _YoursMarker()
          else if (hop.libraryUri != null)
            OriginChip(origin: origin),
          if (_canOpen)
            _OpenSourceButton(
              libraryUri: hop.libraryUri!,
              onOpenSource: onOpenSource!,
            ),
        ],
      ),
    );
  }
}

/// The "yours" marker on the anchor hop — where app code holds the leak.
class _YoursMarker extends StatelessWidget {
  const _YoursMarker();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.my_location, size: 12, color: RadarColors.violet),
        const SizedBox(width: 3),
        Text(
          'yours',
          style: RadarTypography.monoLabel.copyWith(
            color: RadarColors.violet,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _OpenSourceButton extends StatelessWidget {
  const _OpenSourceButton({
    required this.libraryUri,
    required this.onOpenSource,
  });

  final Uri libraryUri;
  final Future<bool> Function(Uri libraryUri) onOpenSource;

  Future<void> _open(BuildContext context) async {
    // Capture the messenger before the await so a false result can toast
    // honestly without reaching across the async gap for context.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final opened = await onOpenSource(libraryUri);
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open source for $libraryUri')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.open_in_new, size: 13),
      tooltip: 'Open in editor',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
      color: RadarColors.text60,
      onPressed: () => _open(context),
    );
  }
}
