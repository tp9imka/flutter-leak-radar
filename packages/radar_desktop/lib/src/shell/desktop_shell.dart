import 'dart:async';

import 'package:flutter/material.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/native_profiling_controller.dart';
import '../app/desktop_view.dart';
import '../screens/android_capture_screen.dart';
import '../screens/android_compare_screen.dart';
import '../screens/android_ffi_screen.dart';
import '../screens/android_native_screen.dart';
import '../screens/android_session_screen.dart';
import '../screens/compare_screen.dart';
import '../screens/dumps_screen.dart';
import '../screens/histogram_screen.dart';
import '../screens/paths_screen.dart';
import '../screens/trends_screen.dart';
import '../seams/android/perfetto_trace_importer.dart';
import '../seams/desktop_perf_call.dart';
import '../seams/vm_service_uri_connection.dart';
import '../workspace/workspace_controller.dart';
import 'connect_bar.dart';
import 'desktop_rail.dart';
import 'desktop_window_chrome.dart';

/// The window scaffold: custom title bar on top, rail on the left, content on
/// the right. Owns the workspace and routes the selected [DesktopView] to its
/// real screen; locked (perf/stability) views never activate while offline.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, this.connection});

  /// The live VM service connection driving PERFORMANCE/STABILITY. Injectable
  /// for tests; when null, the shell owns its own [VmServiceUriConnection].
  final VmServiceUriConnection? connection;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final WorkspaceController _workspace = WorkspaceController();
  final NativeProfilingController _android = NativeProfilingController(
    const PerfettoTraceImporter(),
    deviceProbe: const AdbDeviceProbe(ProcessAdbRunner()),
    capture: AdbHeapprofdCapture(const ProcessAdbRunner()),
  );
  late final VmServiceUriConnection _connection =
      widget.connection ?? VmServiceUriConnection();
  late final PerfDataController _perf = PerfDataController(
    callExtension: perfCallFor(_connection),
  );
  DesktopView _view = DesktopView.dumps;

  bool get _connected =>
      _connection.state.phase == RadarConnectionPhase.connected;

  @override
  void initState() {
    super.initState();
    unawaited(_workspace.restore());
    _connection.addListener(_onConnectionChanged);
  }

  void _onConnectionChanged() {
    setState(() {});
    if (_connected) unawaited(_perf.refresh());
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionChanged);
    _connection.dispose();
    _perf.dispose();
    _workspace.dispose();
    _android.dispose();
    super.dispose();
  }

  void _select(DesktopView v) {
    // Clamp: never activate a locked (perf/stability) view while offline;
    // ANDROID NATIVE is its own offline workspace, so it is never clamped.
    if (!_connected && !v.isMemory && !v.isAndroid) return;
    setState(() => _view = v);
    // Fetch fresh data once per navigation into a perf/stability view, not
    // on every rebuild.
    if (v.isPerf || v.isStability) unawaited(_perf.refresh());
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
        return TracesView(controller: _perf);
      case DesktopView.frames:
        return FramesView(controller: _perf);
      case DesktopView.errors:
        return ErrorsView(controller: _perf);
      case DesktopView.stalls:
        return StallsView(controller: _perf);
      case DesktopView.androidSession:
        return AndroidSessionScreen(controller: _android);
      case DesktopView.androidNative:
        return AndroidNativeScreen(controller: _android);
      case DesktopView.androidCompare:
        return AndroidCompareScreen(controller: _android);
      case DesktopView.androidFfi:
        return AndroidFfiScreen(controller: _android);
      case DesktopView.androidCapture:
        return AndroidCaptureScreen(controller: _android);
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
            ConnectBar(connection: _connection),
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
