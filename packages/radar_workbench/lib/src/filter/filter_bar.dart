// lib/src/filter/filter_bar.dart

import 'package:flutter/widgets.dart';
import 'package:radar_ui/radar_ui.dart';

import 'filter_expression.dart';

/// A search field plus removable-chip row for the Memory table filter
/// language (see [FilterExpression]).
///
/// Controlled by [expression]: typing re-parses the field text and
/// reports the new expression via [onChanged]; tapping a chip's
/// remove affordance prunes that leaf and reports the simplified
/// expression the same way.
class FilterBar extends StatefulWidget {
  /// Creates a filter bar bound to [expression].
  const FilterBar({
    super.key,
    required this.expression,
    required this.onChanged,
    this.hint = 'filter… e.g. library:app class:Foo',
  });

  /// The current filter value (controlled).
  final FilterExpression expression;

  /// Fires on every text edit and on every chip removal.
  final ValueChanged<FilterExpression> onChanged;

  /// Placeholder text for the search field.
  final String hint;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.expression.text,
  );

  @override
  void didUpdateWidget(FilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerIfExternallyChanged();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Keeps [_controller] aligned with [FilterBar.expression] when it
  /// changes from outside (e.g. a chip removal handled by an ancestor,
  /// or the parent resetting the filter).
  void _syncControllerIfExternallyChanged() {
    final canonical = widget.expression.text;
    if (canonical == _controller.text) return;
    _controller.value = TextEditingValue(
      text: canonical,
      selection: TextSelection.collapsed(offset: canonical.length),
    );
  }

  void _handleTextChanged(String value) {
    widget.onChanged(FilterExpression.parse(value));
  }

  void _handleRemoveChip(int leafId) {
    final next = widget.expression.removeLeaf(leafId);
    _controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.text.length),
    );
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final expression = widget.expression;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: RadarSearchField(
            controller: _controller,
            hint: widget.hint,
            onChanged: _handleTextChanged,
          ),
        ),
        if (expression.error != null)
          _FilterErrorLabel(message: expression.error!)
        else if (expression.chips.isNotEmpty)
          _FilterChipRow(chips: expression.chips, onRemove: _handleRemoveChip),
      ],
    );
  }
}

/// The wrapping row of removable [RadarFilterChip]s below the field.
class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({required this.chips, required this.onRemove});

  final List<FilterChipData> chips;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final chip in chips)
            RadarFilterChip(
              label: '${chip.label} ×',
              selected: true,
              onSelected: () => onRemove(chip.leafId),
            ),
        ],
      ),
    );
  }
}

/// Inline parse-error notice shown in place of the chip row.
class _FilterErrorLabel extends StatelessWidget {
  const _FilterErrorLabel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        message,
        style: RadarTypography.caption.copyWith(color: RadarColors.critical),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
