import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:window_manager/window_manager.dart';

/// The custom title bar: a draggable strip with a left gutter reserved for the
/// macOS traffic lights, a centered "`<workspace>` — Radar Desktop" label, and
/// a right-gutter tool health dot.
class DesktopWindowChrome extends StatelessWidget {
  const DesktopWindowChrome({
    super.key,
    required this.workspaceName,
    this.anyToolMissing = false,
    this.missingToolCount = 0,
    this.onOpenTools,
  });

  final String workspaceName;

  /// Whether any external tool ([ToolsController.anyMissing]) is
  /// currently missing — drives the health dot's color.
  final bool anyToolMissing;

  /// How many tools are missing, shown in the health dot's tooltip.
  final int missingToolCount;

  /// Invoked when the health dot is tapped — the shell wires this to
  /// select the Tools view.
  final VoidCallback? onOpenTools;

  static const double height = 38;
  static const double _trafficLightGutter = 78; // room for macOS buttons

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Container(
        height: height,
        color: RadarColors.bgPanel,
        alignment: Alignment.center,
        child: Row(
          children: [
            const SizedBox(width: _trafficLightGutter),
            Expanded(
              child: Center(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: workspaceName,
                        style: RadarTypography.appBarTitle,
                      ),
                      TextSpan(
                        text: '  —  Radar Desktop',
                        style: RadarTypography.appBarTitle.copyWith(
                          color: RadarColors.text40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(
              width: _trafficLightGutter,
              child: Align(
                alignment: Alignment.centerRight,
                child: _ToolHealthDot(
                  anyMissing: anyToolMissing,
                  missingCount: missingToolCount,
                  onTap: onOpenTools,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small status dot in the title bar: accent (healthy) when every
/// external tool is present, amber when [anyMissing] — tapping it opens
/// the Tools screen via [onTap].
class _ToolHealthDot extends StatelessWidget {
  const _ToolHealthDot({
    required this.anyMissing,
    required this.missingCount,
    this.onTap,
  });

  final bool anyMissing;
  final int missingCount;
  final VoidCallback? onTap;

  static const double _size = 8;

  @override
  Widget build(BuildContext context) {
    final color = anyMissing ? RadarColors.warning : RadarColors.accent;
    final message = anyMissing
        ? '$missingCount tool(s) missing'
        : 'All tools present';

    return Tooltip(
      message: message,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: _size,
            height: _size,
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }
}
