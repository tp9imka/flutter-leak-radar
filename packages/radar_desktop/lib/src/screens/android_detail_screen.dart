import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

import '../android/module_palette.dart';
import '../android/native_profiling_controller.dart';

/// File types accepted by the "Add symbols" action.
const List<XTypeGroup> _symbolStoreTypes = [
  XTypeGroup(label: 'Symbol store', extensions: ['json']),
];

/// Callsite/module drill-down opened from the Native still-live table's `›`
/// button (see `docs/flutter_radar_android_profiling` §4.4): the attributed
/// module, still-live/allocation totals, that module's still-live trend
/// across imported checkpoints, and the full native call stack at the
/// current fidelity.
class AndroidDetailScreen extends StatelessWidget {
  const AndroidDetailScreen({
    super.key,
    required this.controller,
    required this.callsite,
  });

  final NativeProfilingController controller;

  /// The callsite this screen drills into. A snapshot taken at tap time —
  /// see [_addSymbols] for why importing a symbol store pops back to the
  /// table rather than re-resolving this instance in place.
  final NativeCallsite callsite;

  /// Opens a file picker for a symbol-store JSON file, imports it, then
  /// pops back to the still-live table. The table re-derives its rows from
  /// [NativeProfilingController.selectedSymbolized] and will show the
  /// newly-resolved function names; this screen does not patch [callsite]
  /// in place because a frame's [NativeCallsite.signature] — its only
  /// stable cross-checkpoint identity — is itself derived from function
  /// names, so it changes the moment symbolization succeeds.
  ///
  /// A failed import (bad file, malformed JSON) never pops: it surfaces
  /// [NativeProfilingController.errorMessage] via a [SnackBar] instead,
  /// matching `dumps_screen.dart`'s import-failure handling.
  Future<void> _addSymbols(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: _symbolStoreTypes);
    if (file == null) return;
    await controller.importSymbolStore(file.path);
    if (!context.mounted) return;
    if (controller.state == NativeImportState.error) {
      _showError(context, 'Import failed: ${controller.errorMessage}');
      return;
    }
    Navigator.of(context).pop();
  }

  /// Per-checkpoint still-live bytes for [module] across every imported
  /// checkpoint, in import order. Symbolization never changes module
  /// attribution (only function names), so this reads raw checkpoints
  /// directly rather than [NativeProfilingController.selectedSymbolized].
  /// A checkpoint with no callsites attributed to [module] reads `0` — an
  /// honest zero, never omitted or guessed.
  List<int> _moduleTrend(String module) => [
    for (final checkpoint in controller.checkpoints)
      _stillLiveBytesFor(checkpoint, module),
  ];

  /// [module]'s still-live bytes within [checkpoint], or `0` when the
  /// checkpoint has no callsites attributed to it.
  int _stillLiveBytesFor(NativeHeapProfile checkpoint, String module) {
    for (final summary in summarizeByModule(checkpoint)) {
      if (summary.module == module) return summary.stillLiveBytes;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Callsite detail')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          // Recomputed on every notify (not hoisted to the outer build) so
          // the banner re-evaluates after a symbol-store import — see
          // [_addSymbols].
          final module = attributedModule(callsite);
          final kind = moduleKind(attributedFrame(callsite)?.module ?? '');
          final attributed = attributedFrame(callsite);
          final anySymbolized = callsite.frames.any(
            (frame) => isFrameSymbolized(frame.function),
          );
          // Allocator leaf frames (malloc/calloc/...) are named without any
          // symbol store, so `anySymbolized` alone would stay true on real
          // traces even when the callsite's actual caller is unresolved.
          // Gate the banner on the attributed (allocator-skipped) frame
          // instead, matching `AndroidNativeCallsiteRow`.
          final attributedSymbolized =
              attributed != null && isFrameSymbolized(attributed.function);
          final showAddSymbolsBanner =
              !attributedSymbolized && !controller.isSymbolized;
          final trend = _moduleTrend(module);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ModuleHeader(module: module, kind: kind),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: RadarMetricTile(
                        label: 'still-live',
                        value: fmtBytes(callsite.stillLiveBytes),
                        severity: RadarSeverity.healthy,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: RadarMetricTile(
                        label: 'live allocations',
                        value: '${callsite.stillLiveCount}',
                        severity: RadarSeverity.healthy,
                      ),
                    ),
                  ],
                ),
                if (trend.length > 1) ...[
                  const SizedBox(height: 20),
                  _ModuleTrend(series: trend),
                ],
                if (showAddSymbolsBanner) ...[
                  const SizedBox(height: 20),
                  RadarBanner(
                    severity: RadarSeverity.warning,
                    message: 'Function names unavailable — add a symbol store',
                    action: FilledButton(
                      onPressed: () => _addSymbols(context),
                      child: const Text('Add symbols'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  anySymbolized
                      ? 'Native call stack'
                      : 'Native call stack '
                            '· module-only',
                  style: RadarTypography.appBarTitle,
                ),
                const SizedBox(height: 8),
                RadarStackList(
                  frames: [for (final frame in callsite.frames) _frame(frame)],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Maps one [NativeFrame] to its [RadarStackFrame] presentation: the
  /// resolved function when symbolized, otherwise the raw address (already
  /// what an unsymbolized [NativeFrame.function] holds) so it never
  /// duplicates the dimmed [RadarStackFrame.module] beside it — falling
  /// back to the module's short name only for the edge case of a frame
  /// with neither a function nor a module.
  RadarStackFrame _frame(NativeFrame frame) {
    final symbolized = isFrameSymbolized(frame.function);
    final text = frame.function.isNotEmpty
        ? frame.function
        : moduleShortName(frame.module);
    return RadarStackFrame(
      text: text,
      module: moduleShortName(frame.module),
      tag: symbolized
          ? null
          : const RadarTag(
              label: 'MODULE-ONLY',
              severity: RadarSeverity.warning,
            ),
    );
  }
}

/// The attributed module name, its kind dot, and kind label.
class _ModuleHeader extends StatelessWidget {
  const _ModuleHeader({required this.module, required this.kind});

  final String module;
  final NativeModuleKind kind;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        RadarModuleDot(color: moduleKindColor(kind)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            module.isEmpty ? '(unknown module)' : module,
            style: RadarTypography.appBarTitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Text(moduleKindLabel(kind), style: RadarTypography.monoLabel),
      ],
    );
  }
}

/// Module still-live across checkpoints — a small trend strip, the
/// nice-to-have from `docs/flutter_radar_android_profiling` §4.4.
class _ModuleTrend extends StatelessWidget {
  const _ModuleTrend({required this.series});

  final List<int> series;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Module still-live across checkpoints',
          style: RadarTypography.monoLabel,
        ),
        const SizedBox(height: 6),
        RadarSparkline(series: series, color: RadarColors.accent),
      ],
    );
  }
}

/// Shows a failure [message] via the nearest [ScaffoldMessenger]. No-ops if
/// [context] is no longer mounted (guards the async gap between the failing
/// import and this callback) or if no messenger is present (e.g. a widget
/// test that pumps the screen without one). Mirrors `dumps_screen.dart`'s
/// `_showError`.
void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}
