import 'package:flutter/material.dart';

/// Fixed-width, right-aligned header cell that scales its content down when
/// the label + sort arrow exceed the column width (e.g. at high font scales
/// in Chrome). Data rows use a plain `SizedBox` of the same width so columns
/// line up exactly with the header.
class SortHeaderCell extends StatelessWidget {
  const SortHeaderCell({super.key, required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: child,
        ),
      ),
    );
  }
}
