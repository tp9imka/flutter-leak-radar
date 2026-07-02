import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../app/desktop_view.dart';
import 'desktop_rail.dart';
import 'desktop_window_chrome.dart';

/// The window scaffold: custom title bar on top, rail on the left, content on
/// the right. Content is a placeholder per view in Phase 2a — Phase 2b swaps in
/// the real workspace + screens.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  DesktopView _view = DesktopView.dumps;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: radarDarkTheme(),
      child: Scaffold(
        backgroundColor: RadarColors.bgPage,
        body: Column(
          children: [
            const DesktopWindowChrome(workspaceName: 'untitled workspace'),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DesktopRail(
                    current: _view,
                    connected: false,
                    onSelect: (v) => setState(() => _view = v),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: RadarColors.bgPage,
                      child: Center(
                        child: Text(
                          '${_view.label} — coming in Phase 2b',
                          style: RadarTypography.body,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
