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
import '../screens/tools_screen.dart';
import '../screens/trends_screen.dart';
import '../seams/android/lazy_tool_seams.dart';
import '../seams/android/perfetto_trace_importer.dart';
import '../seams/desktop_perf_call.dart';
import '../seams/vm_service_uri_connection.dart';
import '../tools/tools_controller.dart';
import '../workspace/workspace_controller.dart';
import 'connect_bar.dart';
import 'desktop_rail.dart';
import 'desktop_window_chrome.dart';

/// The window scaffold: custom title bar on top, rail on the left, content on
/// the right. Owns the workspace and routes the selected [DesktopView] to its
/// real screen; locked (perf/stability) views never activate while offline.
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key, this.connection, this.tools});

  /// The live VM service connection driving PERFORMANCE/STABILITY. Injectable
  /// for tests; when null, the shell owns its own [VmServiceUriConnection].
  final VmServiceUriConnection? connection;

  /// Discovers/persists the external tools (`trace_processor`, `adb`,
  /// `llvm-symbolizer`, `llvm-readelf`) that ANDROID NATIVE's profiling
  /// seams shell out to. Injectable for tests; when null, the shell owns
  /// its own [ToolsController].
  final ToolsController? tools;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  final WorkspaceController _workspace = WorkspaceController();
  late final ToolsController _tools = widget.tools ?? ToolsController();

  /// Seams read [_tools.resolvedPath] lazily on every call, so a Locate/
  /// Install in the Tools screen takes effect on the next import/capture/
  /// symbolize — no rebuild here, which would lose imported checkpoints.
  late final NativeProfilingController _android = NativeProfilingController(
    PerfettoTraceImporter(
      traceProcessorPath: () =>
          _tools.resolvedPath(ExternalTool.traceProcessor),
    ),
    deviceProbe: AdbDeviceProbe(
      LazyAdbRunner(() => _tools.resolvedPath(ExternalTool.adb)),
    ),
    capture: AdbHeapprofdCapture(
      LazyAdbRunner(() => _tools.resolvedPath(ExternalTool.adb)),
    ),
    symbolStoreBuilder: SymbolStoreBuilder(
      buildIdReader: LazyBuildIdReader(
        () => _tools.resolvedPath(ExternalTool.llvmReadelf),
      ),
      symbolizer: LazySymbolizer(
        () => _tools.resolvedPath(ExternalTool.llvmSymbolizer),
      ),
    ),
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
    _tools.addListener(_onToolsChanged);
    unawaited(_tools.load());
  }

  // Rebuilds so the chrome health dot and any missing-tool banners (see the
  // Tools screen work) reflect the latest probe/locate/install result. The
  // profiling seams themselves need no rebuild — they read `_tools` lazily.
  void _onToolsChanged() => setState(() {});

  void _onConnectionChanged() {
    setState(() {
      // Dropped connection while a locked (perf/stability) view was
      // showing: fall back to a MEMORY view so no stale perf view lingers
      // behind the re-locked rail.
      if (!_connected && (_view.isPerf || _view.isStability)) {
        _view = DesktopView.dumps;
      }
    });
    if (_connected) unawaited(_perf.refresh());
  }

  @override
  void dispose() {
    _connection.removeListener(_onConnectionChanged);
    // Only dispose a connection/tools controller we created; an injected
    // one belongs to the caller.
    if (widget.connection == null) _connection.dispose();
    // Remove the listener before disposing so a probe/locate/install call
    // still in flight can't drive a setState after this State is gone.
    _tools.removeListener(_onToolsChanged);
    if (widget.tools == null) _tools.dispose();
    _perf.dispose();
    _workspace.dispose();
    _android.dispose();
    super.dispose();
  }

  void _select(DesktopView v) {
    // Clamp: never activate a locked (perf/stability) view while offline;
    // ANDROID NATIVE is its own offline workspace, so it is never clamped;
    // Tools is how a missing tool gets fixed in the first place, so it is
    // never clamped either.
    if (!_connected && !v.isMemory && !v.isAndroid && !v.isTools) return;
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
        return AndroidCaptureScreen(
          controller: _android,
          tools: _tools,
          onOpenTools: () => _select(DesktopView.tools),
        );
      case DesktopView.tools:
        return ToolsScreen(controller: _tools);
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
            DesktopWindowChrome(
              workspaceName: 'untitled workspace',
              anyToolMissing: _tools.anyMissing,
              missingToolCount: _tools.statuses.where((s) => !s.found).length,
              onOpenTools: () => _select(DesktopView.tools),
            ),
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
