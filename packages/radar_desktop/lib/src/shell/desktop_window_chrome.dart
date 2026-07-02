import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:window_manager/window_manager.dart';

/// The custom title bar: a draggable strip with a left gutter reserved for the
/// macOS traffic lights and a centered "`<workspace>` — Radar Desktop" label.
class DesktopWindowChrome extends StatelessWidget {
  const DesktopWindowChrome({super.key, required this.workspaceName});

  final String workspaceName;

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
            const SizedBox(width: _trafficLightGutter),
          ],
        ),
      ),
    );
  }
}
