import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../app/desktop_view.dart';
import '../screens/compare_screen.dart';
import '../screens/dumps_screen.dart';
import '../screens/histogram_screen.dart';
import '../screens/paths_screen.dart';
import '../screens/trends_screen.dart';
import '../workspace/workspace_controller.dart';
import 'desktop_rail.dart';
import 'desktop_window_chrome.dart';

/// The window scaffold: custom title bar on top, rail on the left, content on
/// the right. Owns the workspace and routes the selected [DesktopView] to its
/// real screen; locked (perf/stability) views never activate while offline.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final WorkspaceController _workspace = WorkspaceController();
  DesktopView _view = DesktopView.dumps;
  final bool _connected = false; // Phase 3 flips this

  @override
  void dispose() {
    _workspace.dispose();
    super.dispose();
  }

  void _select(DesktopView v) {
    // Clamp: never activate a locked (perf/stability) view while offline.
    if (!_connected && !v.isMemory) return;
    setState(() => _view = v);
  }

  Widget _content() {
    switch (_view) {
      case DesktopView.dumps:
        return DumpsScreen(
          workspace: _workspace,
          onOpenHistogram: (id) {
            _workspace.openDump(id);
            setState(() => _view = DesktopView.histogram);
          },
        );
      case DesktopView.histogram:
        return HistogramScreen(workspace: _workspace);
      case DesktopView.paths:
        return PathsScreen(workspace: _workspace);
      case DesktopView.compare:
        return CompareScreen(workspace: _workspace);
      case DesktopView.trends:
        return TrendsScreen(workspace: _workspace);
      case DesktopView.traces:
      case DesktopView.frames:
      case DesktopView.errors:
      case DesktopView.stalls:
        // Locked offline; unreachable via the clamped rail, but render a
        // stub in case it is ever reached directly.
        return Center(
          child: Text(
            '${_view.label} — connect a VM service (Phase 3)',
            style: RadarTypography.body,
          ),
        );
    }
  }

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
                    connected: _connected,
                    onSelect: _select,
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: RadarColors.bgPage,
                      child: _content(),
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
