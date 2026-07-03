// lib/src/widgets/radar_expandable_row.dart

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';

/// A tappable header row that expands to reveal [child].
///
/// The leading chevron rotates a quarter turn on expand, respecting
/// [MediaQuery.disableAnimationsOf] (reduced-motion preference). Used
/// for the still-live table's module rows expanding to their call
/// sites.
class RadarExpandableRow extends StatefulWidget {
  const RadarExpandableRow({
    super.key,
    required this.header,
    required this.child,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  /// The always-visible tappable row content, shown beside the chevron.
  final Widget header;

  /// Content revealed below the header when expanded.
  final Widget child;

  /// Whether the row starts expanded.
  final bool initiallyExpanded;

  /// Called with the new expansion state whenever the row is toggled.
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<RadarExpandableRow> createState() => _RadarExpandableRowState();
}

class _RadarExpandableRowState extends State<RadarExpandableRow> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpansionChanged?.call(_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: RadarDensity.rowHeight,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RadarDensity.rowHPad,
                vertical: RadarDensity.rowVPad,
              ),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    child: const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: RadarColors.text40,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: widget.header),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) widget.child,
      ],
    );
  }
}
