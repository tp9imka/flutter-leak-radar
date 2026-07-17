import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/native_profiling_controller.dart';
import '../app/desktop_view.dart';
import '../onboarding/first_run_guide.dart';
import '../screens/android_capture_screen.dart';
import '../screens/android_compare_screen.dart';
import '../screens/android_ffi_screen.dart';
import '../screens/android_native_screen.dart';
import '../screens/android_session_screen.dart';
import '../screens/clusters_screen.dart';
import '../screens/compare_screen.dart';
import '../screens/device_monitor_controller.dart';
import '../screens/device_monitor_screen.dart';
import '../screens/dumps_screen.dart';
import '../screens/histogram_screen.dart';
import '../screens/live_memory_controller.dart';
import '../screens/paths_screen.dart';
import '../screens/tools_screen.dart';
import '../screens/trends_screen.dart';
import '../seams/android/lazy_tool_seams.dart';
import '../seams/android/perfetto_trace_importer.dart';
import '../seams/desktop_memory_poll.dart';
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
  const DesktopShell({
    super.key,
    this.connection,
    this.tools,
    this.workspace,
    this.deviceMonitor,
    this.liveMemory,
    this.guide,
  });

  /// The live VM service connection driving PERFORMANCE/STABILITY. Injectable
  /// for tests; when null, the shell owns its own [VmServiceUriConnection].
  final VmServiceUriConnection? connection;

  /// The Device Monitor import-first controller. Injectable for tests; when
  /// null, the shell owns its own.
  final DeviceMonitorController? deviceMonitor;

  /// The Device Monitor live-poll controller. Injectable for tests; when null,
  /// the shell owns one wired to [connection]'s `getMemoryUsage`.
  final LiveMemoryController? liveMemory;

  /// Discovers/persists the external tools (`trace_processor`, `adb`,
  /// `llvm-symbolizer`, `llvm-readelf`) that ANDROID NATIVE's profiling
  /// seams shell out to. Injectable for tests; when null, the shell owns
  /// its own [ToolsController].
  final ToolsController? tools;

  /// The offline workspace. Injectable for tests (e.g. to seed a durable store
  /// or a restore refusal); when null, the shell owns its own.
  final WorkspaceController? workspace;

  /// Drives the first-run onboarding tour (welcome → five spotlights →
  /// finish). Injectable for tests; when null, the shell owns its own
  /// [FirstRunGuideController] backed by [FileFirstRunStore].
  final FirstRunGuideController? guide;

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  late final WorkspaceController _workspace =
      widget.workspace ?? WorkspaceController();
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
  late final DeviceMonitorController _deviceMonitor =
      widget.deviceMonitor ?? DeviceMonitorController();
  late final LiveMemoryController _liveMemory =
      widget.liveMemory ??
      LiveMemoryController(poll: memoryPollFor(_connection));
  late final FirstRunGuideController _guide =
      widget.guide ?? FirstRunGuideController();
  DesktopView _view = DesktopView.dumps;

  // Anchors for the first-run guide's spotlight overlay: the connect bar
  // plus one key per rail group. Passed into `DesktopRail`/`ConnectBar`
  // and collected into `_guideAnchors` below, so the overlay can measure
  // each render box without any hard-coded coordinates.
  final GlobalKey _connectBarKey = GlobalKey();
  final GlobalKey _memoryGroupKey = GlobalKey();
  final GlobalKey _performanceGroupKey = GlobalKey();
  final GlobalKey _stabilityGroupKey = GlobalKey();
  final GlobalKey _androidGroupKey = GlobalKey();
  final GlobalKey _toolsGroupKey = GlobalKey();
  final GlobalKey _healthDotKey = GlobalKey();

  late final Map<GuideStep, GlobalKey> _guideAnchors = {
    GuideStep.connectBar: _connectBarKey,
    GuideStep.memory: _memoryGroupKey,
    GuideStep.performance: _performanceGroupKey,
    GuideStep.stability: _stabilityGroupKey,
    GuideStep.android: _androidGroupKey,
    GuideStep.tools: _toolsGroupKey,
  };

  /// The guide step a rail-group scroll-into-view was last scheduled
  /// for — guards against re-scheduling every rebuild once a step has
  /// already been handled.
  int? _lastGuideScrollStep;

  bool get _connected =>
      _connection.state.phase == RadarConnectionPhase.connected;

  @override
  void initState() {
    super.initState();
    unawaited(_workspace.restore());
    _connection.addListener(_onConnectionChanged);
    _tools.addListener(_onToolsChanged);
    unawaited(_tools.load());
    _guide.addListener(_onGuideChanged);
    unawaited(_guide.load());
  }

  void _onGuideChanged() {
    setState(() {});
    _scrollGuideAnchorIntoView();
  }

  /// Ensures the rail group the guide is about to spotlight is actually
  /// visible in the (scrollable) rail before the overlay measures it.
  /// An instant (`Duration.zero`) jump, not an animated scroll — so the
  /// anchor already sits at its final position by the time the guide's
  /// next frame measures its render box; animating here would risk the
  /// overlay snapshotting the anchor mid-scroll.
  void _scrollGuideAnchorIntoView() {
    final step = _guide.step;
    if (!_guide.open || step == _lastGuideScrollStep) return;
    final keys = _railKeysForGuideStep(step);
    if (keys.isEmpty) return;
    _lastGuideScrollStep = step;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final key in keys) {
        final anchorContext = key.currentContext;
        if (anchorContext == null) continue;
        unawaited(
          Scrollable.ensureVisible(anchorContext, duration: Duration.zero),
        );
      }
    });
  }

  /// The rail group key(s) spotlighted at guide step [step] (1..5), or
  /// none for the connect-bar step (always visible, not in the
  /// scrollable rail). Step 3 unions PERFORMANCE and STABILITY, so both
  /// are scrolled into view together.
  List<GlobalKey> _railKeysForGuideStep(int step) => switch (step) {
    2 => [_memoryGroupKey],
    3 => [_performanceGroupKey, _stabilityGroupKey],
    4 => [_androidGroupKey],
    5 => [_toolsGroupKey],
    _ => const [],
  };

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
    // A dropped connection stops live polling; import-first stays usable.
    if (!_connected) _liveMemory.stop();
    // Connecting while already parked on the Device Monitor must begin live
    // polling here — otherwise the live tab would sit at "0 samples" until the
    // user navigated away and back.
    if (_connected && _view.isDeviceMonitor) _liveMemory.start();
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
    _guide.removeListener(_onGuideChanged);
    if (widget.guide == null) _guide.dispose();
    _perf.dispose();
    // Only dispose controllers we created; injected ones belong to the caller.
    if (widget.deviceMonitor == null) _deviceMonitor.dispose();
    if (widget.liveMemory == null) _liveMemory.dispose();
    // Only dispose a workspace we created; an injected one belongs to the test.
    if (widget.workspace == null) _workspace.dispose();
    _android.dispose();
    super.dispose();
  }

  /// The first ready (`'device'`-state) Android device's serial, or null
  /// if none is ready — `adb` then falls back to its single-device
  /// default, which is acceptable for this v1 scan affordance.
  String? get _readyDeviceSerial {
    for (final device in _android.devices) {
      if (device.isReady) return device.serial;
    }
    return null;
  }

  void _select(DesktopView v) {
    // Clamp: never activate a locked (perf/stability) view while offline;
    // ANDROID NATIVE and DEVICE MONITOR are offline-capable (import-first), so
    // they are never clamped; Tools is how a missing tool gets fixed in the
    // first place, so it is never clamped either.
    if (!_connected &&
        !v.isMemory &&
        !v.isAndroid &&
        !v.isDeviceMonitor &&
        !v.isTools) {
      return;
    }
    // Live polling runs only while the Device Monitor is showing and a live
    // connection exists; stop it whenever we navigate elsewhere.
    if (v.isDeviceMonitor && _connected) {
      _liveMemory.start();
    } else {
      _liveMemory.stop();
    }
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
      case DesktopView.clusters:
        return ClustersScreen(workspace: _workspace);
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
      case DesktopView.deviceMonitor:
        return DeviceMonitorScreen(
          controller: _deviceMonitor,
          live: _liveMemory,
          connected: _connected,
          onImportPrimary: () => _pickAndImport(comparison: false),
          onImportComparison: () => _pickAndImport(comparison: true),
        );
      case DesktopView.tools:
        return ToolsScreen(controller: _tools);
    }
  }

  /// Opens a file picker for a Device Monitor artifact (a session
  /// `timeline.json` or a radar_ci `run.json`) and imports it. A cancelled
  /// pick is a no-op; a bad file surfaces through the controller's error
  /// state, never a crash.
  static const List<XTypeGroup> _monitorFileTypes = [
    XTypeGroup(label: 'Radar artifact', extensions: ['json']),
  ];

  Future<void> _pickAndImport({required bool comparison}) async {
    final file = await openFile(acceptedTypeGroups: _monitorFileTypes);
    if (file == null) return;
    if (comparison) {
      await _deviceMonitor.importComparison(file.path);
    } else {
      await _deviceMonitor.importPrimary(file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reads the resolved adb path lazily on every scan tap (same seam
    // `_android`'s deviceProbe/capture use), so a Locate/Install in the
    // Tools screen takes effect without rebuilding this controller.
    final discovery = AndroidVmServiceDiscovery(
      LazyAdbRunner(() => _tools.resolvedPath(ExternalTool.adb)),
    );
    return Theme(
      data: radarDarkTheme(),
      child: Scaffold(
        backgroundColor: RadarColors.bgPage,
        body: Stack(
          children: [
            Column(
              children: [
                DesktopWindowChrome(
                  workspaceName: 'untitled workspace',
                  anyToolMissing: _tools.anyMissing,
                  missingToolCount: _tools.statuses
                      .where((s) => !s.found)
                      .length,
                  onOpenTools: () => _select(DesktopView.tools),
                  onReopenGuide: _guide.reopen,
                  healthDotKey: _healthDotKey,
                ),
                KeyedSubtree(
                  key: _connectBarKey,
                  child: ConnectBar(
                    connection: _connection,
                    onScanDevice: _android.canCapture
                        ? () => discovery.discoverWsUri(
                            serial: _readyDeviceSerial,
                          )
                        : null,
                  ),
                ),
                ListenableBuilder(
                  listenable: _workspace,
                  builder: (context, _) {
                    final refusal = _workspace.restoreRefusal;
                    if (refusal == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: RadarBanner(
                        message: refusal,
                        severity: RadarSeverity.warning,
                        action: OutlinedButton(
                          onPressed: _workspace.startNewSession,
                          child: const Text('Start new'),
                        ),
                      ),
                    );
                  },
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DesktopRail(
                        current: _view,
                        connected: _connected,
                        onSelect: _select,
                        memoryGroupKey: _memoryGroupKey,
                        performanceGroupKey: _performanceGroupKey,
                        stabilityGroupKey: _stabilityGroupKey,
                        androidGroupKey: _androidGroupKey,
                        toolsGroupKey: _toolsGroupKey,
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
            // Overlays everything above: self-hides (`SizedBox.shrink`)
            // whenever `_guide.open` is false, so it's inert until the
            // first run (or a `?` re-open) shows it.
            Positioned.fill(
              child: FirstRunGuide(controller: _guide, anchors: _guideAnchors),
            ),
          ],
        ),
      ),
    );
  }
}
