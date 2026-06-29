// lib/src/widgets/radar_sort_header.dart

import 'package:flutter/widgets.dart';

import '../tokens/colors.dart';
import '../tokens/typography.dart';

/// Sort direction for a [RadarSortHeader].
enum RadarSortDirection { ascending, descending }

/// A tappable column-header label that indicates sort state.
///
/// When [sortKey] matches [activeSortKey] the header is "active" and
/// shows a ↓ or ↑ arrow in [RadarColors.accent] (the design mandates
/// accent green for active sort arrows). Tapping the header calls
/// [onSort] with the toggled direction if already active, or with
/// [RadarSortDirection.descending] if not yet active.
class RadarSortHeader extends StatelessWidget {
  const RadarSortHeader({
    super.key,
    required this.label,
    required this.sortKey,
    required this.activeSortKey,
    required this.direction,
    required this.onSort,
    this.textAlign = TextAlign.right,
  });

  /// Text label for this column (e.g., 'avg', 'count', 'total').
  final String label;

  /// Unique identifier for this column used in [onSort] callbacks.
  final String sortKey;

  /// The currently active sort column key; when equal to [sortKey]
  /// this header is active and shows a direction arrow.
  final String activeSortKey;

  /// Current sort direction; used when this header is [activeSortKey].
  final RadarSortDirection direction;

  /// Callback fired on tap; receives the [sortKey] and the new direction.
  final void Function(String key, RadarSortDirection dir) onSort;

  /// Text alignment for the label (defaults to right for numeric columns).
  final TextAlign textAlign;

  bool get _isActive => sortKey == activeSortKey;

  String get _arrow => switch (direction) {
    RadarSortDirection.descending => '↓',
    RadarSortDirection.ascending => '↑',
  };

  RadarSortDirection get _nextDirection => switch (direction) {
    RadarSortDirection.descending => RadarSortDirection.ascending,
    RadarSortDirection.ascending => RadarSortDirection.descending,
  };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final newDir = _isActive
            ? _nextDirection
            : RadarSortDirection.descending;
        onSort(sortKey, newDir);
      },
      child: Row(
        mainAxisAlignment: textAlign == TextAlign.right
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: RadarTypography.monoLabel.copyWith(
              color: _isActive ? RadarColors.accent : RadarColors.text40,
            ),
            textAlign: textAlign,
          ),
          if (_isActive) ...[
            const SizedBox(width: 3),
            Text(
              _arrow,
              style: RadarTypography.monoLabel.copyWith(
                color: RadarColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
