import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../android/native_profiling_controller.dart';

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
/// `docs/flutter_radar_android_profiling` §4.6). Everything here runs
/// offline against already-captured files; driving `adb` + heapprofd
/// against a connected device is Phase 4 — the "Run device capture" action
/// is rendered disabled until then.
class AndroidCaptureScreen extends StatefulWidget {
  const AndroidCaptureScreen({super.key, required this.controller});

  final NativeProfilingController controller;

  @override
  State<AndroidCaptureScreen> createState() => _AndroidCaptureScreenState();
}

class _AndroidCaptureScreenState extends State<AndroidCaptureScreen> {
  NativeProfilingController get _controller => widget.controller;

  static String _labelFor(String path) =>
      path.split(Platform.pathSeparator).last;

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
                _ImportActionRow(
                  icon: Icons.phone_android,
                  label: 'Run device capture',
                  helper: '(Phase 4)',
                  onPressed: null,
                  tooltip: 'adb + heapprofd device capture lands in Phase 4',
                ),
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

/// One import action: a button plus its always-visible helper text,
/// optionally wrapped in a [Tooltip] (used for the disabled device-capture
/// action).
class _ImportActionRow extends StatelessWidget {
  const _ImportActionRow({
    required this.icon,
    required this.label,
    required this.helper,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final String helper;
  final Future<void> Function()? onPressed;
  final String? tooltip;

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
            tooltip == null
                ? button
                : Tooltip(message: tooltip!, child: button),
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
