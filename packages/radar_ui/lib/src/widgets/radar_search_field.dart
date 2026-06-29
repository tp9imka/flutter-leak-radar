// lib/src/widgets/radar_search_field.dart

import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/density.dart';
import '../tokens/typography.dart';

/// A mono-font text field for filtering/searching Radar list views.
///
/// Styled with the Radar dark input treatment: [RadarColors.bgInput]
/// fill, hairline border, and [RadarTypography.monoInput] text style.
///
/// Hint text defaults to 'filter…'; override via [hint].
class RadarSearchField extends StatelessWidget {
  const RadarSearchField({
    super.key,
    required this.onChanged,
    this.controller,
    this.hint = 'filter…',
  });

  /// Called with the current query string on every keystroke.
  final ValueChanged<String> onChanged;

  /// Optional controller for external query management.
  final TextEditingController? controller;

  /// Placeholder text shown when the field is empty.
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: RadarTypography.monoInput,
      cursorColor: RadarColors.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: RadarTypography.monoInput.copyWith(
          color: RadarColors.text25,
        ),
        filled: true,
        fillColor: RadarColors.bgInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: RadarDensity.rowVPad,
        ),
        prefixIcon: const Icon(
          Icons.search,
          size: 16,
          color: RadarColors.text25,
        ),
        border: OutlineInputBorder(
          borderSide: const BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: RadarColors.hairline08,
            width: RadarDensity.hairline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: RadarColors.accent,
            width: RadarDensity.hairline,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
