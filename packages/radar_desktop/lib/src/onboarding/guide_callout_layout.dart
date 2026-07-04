import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Places the spotlight callout relative to its anchor: right-of-anchor
/// by default (rail steps), below for the connect bar; clamps within
/// the available space and flips to the opposite side on overflow. A
/// null [anchor] (not yet measured) centers the callout instead.
class GuideCalloutLayoutDelegate extends SingleChildLayoutDelegate {
  const GuideCalloutLayoutDelegate({
    required this.anchor,
    required this.preferBelow,
  });

  final Rect? anchor;
  final bool preferBelow;

  static const double _gap = 16;
  static const double _margin = 16;
  static const double _maxWidth = 330;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = constraints.maxWidth - _margin * 2;
    final width = available.isFinite
        ? math.min(_maxWidth, available)
        : _maxWidth;
    return BoxConstraints(maxWidth: width > 0 ? width : constraints.maxWidth);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final anchor = this.anchor;
    if (anchor == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    double left;
    double top;
    if (preferBelow) {
      top = anchor.bottom + _gap;
      if (top + childSize.height > size.height - _margin) {
        top = anchor.top - _gap - childSize.height;
      }
      left = anchor.left;
    } else {
      left = anchor.right + _gap;
      if (left + childSize.width > size.width - _margin) {
        left = anchor.left - _gap - childSize.width;
      }
      top = anchor.top;
    }

    final maxLeft = math.max(_margin, size.width - childSize.width - _margin);
    final maxTop = math.max(_margin, size.height - childSize.height - _margin);
    return Offset(left.clamp(_margin, maxLeft), top.clamp(_margin, maxTop));
  }

  @override
  bool shouldRelayout(covariant GuideCalloutLayoutDelegate oldDelegate) =>
      anchor != oldDelegate.anchor || preferBelow != oldDelegate.preferBelow;
}
