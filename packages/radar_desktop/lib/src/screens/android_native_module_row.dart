import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/module_palette.dart';

/// Column widths shared between the still-live table's header
/// (`android_native_screen.dart`) and its rows below.
const double nativeColStillLiveWidth = 96;
const double nativeColAllocsWidth = 76;
const double nativeColGrowthWidth = 96;

/// A ranked module row, expanding to its callsites.
class AndroidNativeModuleRow extends StatelessWidget {
  const AndroidNativeModuleRow({
    super.key,
    required this.summary,
    required this.deltaBytes,
    required this.onOpenDetail,
  });

  final NativeModuleSummary summary;

  /// `null` when there is no previous checkpoint to diff against.
  final int? deltaBytes;

  final ValueChanged<NativeCallsite>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return RadarExpandableRow(
      header: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                RadarModuleDot(color: moduleKindColor(summary.kind)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    summary.module,
                    style: RadarTypography.monoBody.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  moduleKindLabel(summary.kind),
                  style: RadarTypography.monoLabel,
                ),
              ],
            ),
          ),
          SizedBox(
            width: nativeColStillLiveWidth,
            child: Text(
              fmtBytes(summary.stillLiveBytes),
              style: RadarTypography.monoNumber.copyWith(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: nativeColAllocsWidth,
            child: Text(
              '${summary.stillLiveCount}',
              style: RadarTypography.monoNumber.copyWith(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: nativeColGrowthWidth,
            child: _DeltaText(bytes: deltaBytes),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final callsite in summary.callsites)
              AndroidNativeCallsiteRow(
                callsite: callsite,
                onOpenDetail: onOpenDetail,
              ),
          ],
        ),
      ),
    );
  }
}

/// A module's callsite row: its top (attributed) frame at the current
/// fidelity, still-live totals, and a `›` into the (future) detail view.
class AndroidNativeCallsiteRow extends StatelessWidget {
  const AndroidNativeCallsiteRow({
    super.key,
    required this.callsite,
    required this.onOpenDetail,
  });

  final NativeCallsite callsite;
  final ValueChanged<NativeCallsite>? onOpenDetail;

  /// A frame is symbolized when its function is non-empty and not a raw
  /// `0x…` address — never guessed beyond what the symbol store resolved.
  static bool _isFrameSymbolized(String function) =>
      function.isNotEmpty && !function.startsWith('0x');

  @override
  Widget build(BuildContext context) {
    final frame = attributedFrame(callsite);
    final symbolized = frame != null && _isFrameSymbolized(frame.function);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    symbolized ? frame.function : attributedModule(callsite),
                    style: RadarTypography.monoBody.copyWith(fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!symbolized) ...[
                  const SizedBox(width: 6),
                  const RadarTag(
                    label: 'MODULE-ONLY',
                    severity: RadarSeverity.warning,
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: nativeColStillLiveWidth,
            child: Text(
              fmtBytes(callsite.stillLiveBytes),
              style: RadarTypography.monoNumber.copyWith(fontSize: 11.5),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: nativeColAllocsWidth,
            child: Text(
              '${callsite.stillLiveCount}',
              style: RadarTypography.monoNumber.copyWith(fontSize: 11.5),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: nativeColGrowthWidth,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              color: RadarColors.text40,
              icon: const Icon(Icons.chevron_right),
              onPressed: onOpenDetail == null
                  ? null
                  : () => onOpenDetail!(callsite),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeltaText extends StatelessWidget {
  const _DeltaText({required this.bytes});

  /// `null` when there is no previous checkpoint to diff against.
  final int? bytes;

  Color _color(int v) {
    if (v > 0) return RadarColors.critical;
    if (v < 0) return RadarColors.accent;
    return RadarColors.text40;
  }

  String _format(int v) {
    final sign = v > 0
        ? '+'
        : v < 0
        ? '-'
        : '';
    return '$sign${fmtBytes(v.abs())}';
  }

  @override
  Widget build(BuildContext context) {
    final v = bytes;
    return Text(
      v == null ? '—' : _format(v),
      style: RadarTypography.monoNumber.copyWith(
        fontSize: 12,
        color: v == null ? RadarColors.text25 : _color(v),
      ),
      textAlign: TextAlign.right,
    );
  }
}
