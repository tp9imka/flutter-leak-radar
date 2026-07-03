import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

import '../android/native_profiling_controller.dart';
import 'android_capture_form.dart';

/// File types accepted by each import action.
const List<XTypeGroup> _traceTypes = [
  XTypeGroup(label: 'Perfetto trace', extensions: ['pftrace']),
];
const List<XTypeGroup> _symbolStoreTypes = [
  XTypeGroup(label: 'Symbol store', extensions: ['json']),
];
const List<XTypeGroup> _ffiLogTypes = [
  XTypeGroup(label: 'ffi allocation log', extensions: ['json']),
];

/// Entry point for capturing a new heapprofd trace and importing on-disk
/// traces, symbol stores, and FFI allocation logs into the workspace (see
/// `docs/flutter_radar_android_profiling` §4.6). Import actions always run
/// offline against already-captured files; the device-capture flow drives
/// `adb` + heapprofd against a connected device and is only offered when
/// [NativeProfilingController.canCapture] is true (i.e. both capture seams
/// were injected for this build/host).
class AndroidCaptureScreen extends StatefulWidget {
  const AndroidCaptureScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  State<AndroidCaptureScreen> createState() => _AndroidCaptureScreenState();
}

class _AndroidCaptureScreenState extends State<AndroidCaptureScreen> {
  NativeProfilingController get _controller => widget.controller;

  String? _selectedSerial;
  String _packageId = '';
  CaptureMode _mode = CaptureMode.startup;
  int _durationMs = 30000;
  bool _justCaptured = false;

  static String _labelFor(String path) =>
      path.split(Platform.pathSeparator).last;

  @override
  void initState() {
    super.initState();
    if (_controller.canCapture) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshDevices());
      });
    }
  }

  /// Imports the Perfetto trace at [path], or opens a file picker for one
  /// when [path] is omitted (the button path vs. the drag-drop path).
  /// Never rethrows: a failure surfaces via [_controller]'s `state`, which
  /// [_reportIfFailed] turns into a [SnackBar].
  Future<void> _importTraceFrom(String? path) async {
    final resolved =
        path ?? (await openFile(acceptedTypeGroups: _traceTypes))?.path;
    if (resolved == null) return;
    await _controller.importTrace(resolved, label: _labelFor(resolved));
    _reportIfFailed();
  }

  Future<void> _importTrace() => _importTraceFrom(null);

  Future<void> _importSymbolStore() async {
    final file = await openFile(acceptedTypeGroups: _symbolStoreTypes);
    if (file == null) return;
    await _controller.importSymbolStore(file.path);
    _reportIfFailed();
  }

  Future<void> _importFfiLog() async {
    final file = await openFile(acceptedTypeGroups: _ffiLogTypes);
    if (file == null) return;
    await _controller.importFfiLog(file.path);
    _reportIfFailed();
  }

  /// Drag-drop nicety mirroring `dumps_screen.dart`: any dropped `.pftrace`
  /// file imports as a checkpoint, same as the browse button.
  Future<void> _onDrop(DropDoneDetails details) async {
    for (final file in details.files) {
      if (!file.path.endsWith('.pftrace')) continue;
      await _importTraceFrom(file.path);
    }
  }

  /// Surfaces the most recent import failure via a [SnackBar], mirroring
  /// `dumps_screen.dart`'s `_browse` error handling.
  void _reportIfFailed() {
    if (!context.mounted) return;
    if (_controller.state != NativeImportState.error) return;
    _showError(context, 'Import failed: ${_controller.errorMessage}');
  }

  /// Refreshes the connected-device list, then reports a failure if one
  /// occurred. Called once on first build and again from the refresh
  /// button.
  Future<void> _refreshDevices() async {
    await _controller.refreshDevices();
    _reportCaptureIfFailed();
  }

  /// Runs a device capture against [serial] with the form's current
  /// package/mode/duration, then reports success (an inline note) or
  /// failure (a [SnackBar]).
  Future<void> _runCapture(String serial) async {
    setState(() => _justCaptured = false);
    final request = CaptureRequest(
      packageId: _packageId.trim(),
      mode: _mode,
      durationMs: _durationMs,
      serial: serial,
    );
    await _controller.captureAndImport(request);
    if (!mounted) return;
    if (_controller.captureState == CaptureState.error ||
        _controller.state == NativeImportState.error) {
      _reportCaptureIfFailed();
      return;
    }
    setState(() => _justCaptured = true);
  }

  /// Surfaces the most recent capture-flow failure via a [SnackBar]: either
  /// the probe/capture layer (`captureState`) or a downstream trace-parse
  /// failure surfaced through the shared import `state` — a successful
  /// capture is funneled into `importTrace`, which never rethrows on its
  /// own.
  void _reportCaptureIfFailed() {
    if (!context.mounted) return;
    if (_controller.captureState == CaptureState.error) {
      _showError(context, 'Capture failed: ${_controller.captureError}');
      return;
    }
    if (_controller.state == NativeImportState.error) {
      _showError(context, 'Import failed: ${_controller.errorMessage}');
    }
  }

  /// The serial that should be shown as selected: the user's pick if it is
  /// still present AND ready, else the first ready device, else `null`
  /// (no ready device → capture stays disabled).
  String? _resolveSerial(List<AndroidDevice> devices) {
    final ready = devices.where((d) => d.isReady).toList();
    final selected = _selectedSerial;
    if (selected != null && ready.any((d) => d.serial == selected)) {
      return selected;
    }
    return ready.isEmpty ? null : ready.first.serial;
  }

  Widget _deviceCaptureSection() {
    if (!_controller.canCapture) return const NoCaptureDeviceHint();

    final devices = _controller.devices;
    final resolvedSerial = _resolveSerial(devices);
    final captureState = _controller.captureState;
    final busy =
        captureState == CaptureState.capturing ||
        captureState == CaptureState.probing;

    VoidCallback? onCapture;
    if (!busy && _packageId.trim().isNotEmpty) {
      final serial = resolvedSerial;
      if (serial != null) {
        onCapture = () => unawaited(_runCapture(serial));
      }
    }

    return AndroidCaptureForm(
      devices: devices,
      selectedSerial: resolvedSerial,
      probing: captureState == CaptureState.probing,
      capturing: captureState == CaptureState.capturing,
      mode: _mode,
      durationMs: _durationMs,
      justCaptured: _justCaptured,
      onSelectDevice: (serial) => setState(() {
        _selectedSerial = serial;
        _justCaptured = false;
      }),
      onRefreshDevices: busy ? null : () => unawaited(_refreshDevices()),
      onPackageChanged: (value) => setState(() {
        _packageId = value;
        _justCaptured = false;
      }),
      onModeChanged: (mode) => setState(() {
        _mode = mode;
        _justCaptured = false;
      }),
      onDurationChanged: (ms) => setState(() {
        _durationMs = ms;
        _justCaptured = false;
      }),
      onCapture: onCapture,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return DropTarget(
          onDragDone: _onDrop,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Capture / import', style: RadarTypography.appBarTitle),
                const SizedBox(height: 12),
                const _PrerequisitesNote(),
                const SizedBox(height: 20),
                _ImportActionRow(
                  icon: Icons.upload_file,
                  label: 'Import Perfetto trace',
                  helper:
                      '.pftrace with a heapprofd stream · drop a file '
                      'anywhere on this screen',
                  onPressed: _importTrace,
                ),
                const SizedBox(height: 10),
                _deviceCaptureSection(),
                const SizedBox(height: 20),
                Text('Optional inputs', style: RadarTypography.monoLabel),
                const SizedBox(height: 8),
                _ImportActionRow(
                  icon: Icons.text_snippet_outlined,
                  label: 'Attach symbol store',
                  helper: '.json · unlocks function names in native stacks',
                  onPressed: _importSymbolStore,
                ),
                const SizedBox(height: 10),
                _ImportActionRow(
                  icon: Icons.memory,
                  label: 'Import ffi log',
                  helper: '.json · adds the ffi allocations lane',
                  onPressed: _importFfiLog,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Plainly-stated prerequisites and constraints from
/// `docs/flutter_radar_android_profiling` §4.6.
class _PrerequisitesNote extends StatelessWidget {
  const _PrerequisitesNote();

  static const _lines = [
    'Android only · iOS not supported',
    'profile the profile/release build (debug adds allocator noise)',
    'requires a trace_processor binary — set RADAR_TP_BIN or configure '
        'a path',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in _lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $line', style: RadarTypography.caption),
          ),
      ],
    );
  }
}

/// One import action: a button plus its always-visible helper text.
class _ImportActionRow extends StatelessWidget {
  const _ImportActionRow({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String helper;
  final Future<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    final action = onPressed;
    final button = FilledButton.icon(
      onPressed: action == null ? null : () => action(),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgSurface,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            button,
            const SizedBox(width: 12),
            Expanded(child: Text(helper, style: RadarTypography.monoLabel)),
          ],
        ),
      ),
    );
  }
}

/// Shows a failure [message] via the nearest [ScaffoldMessenger]. No-ops if
/// [context] is no longer mounted or if no messenger is present (e.g. a
/// widget test that pumps the screen without one). Mirrors
/// `dumps_screen.dart`'s `_showError`.
void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
