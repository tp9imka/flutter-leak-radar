import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:radar_ui/radar_ui.dart';

import '../tools/tools_controller.dart';

/// The SETUP destination: shows every external CLI tool Radar Desktop
/// shells out to (`trace_processor`, `adb`, `llvm-symbolizer`,
/// `llvm-readelf`), whether each was found and where, and lets the user
/// fix a missing one — install `trace_processor` in one click, or
/// **Locate…** any tool by hand. Always reachable, even offline, since
/// it's how a user resolves the very thing that's blocking them.
class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key, required this.controller});

  /// Owns discovery/persistence for every [ExternalTool]; this screen
  /// only renders [ToolsController.statuses] and drives its actions.
  final ToolsController controller;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  /// True while an install is in flight — disables the Install button
  /// and swaps its icon for a spinner. [ToolsController] has no such
  /// flag of its own (it only tracks the last [installError]), so this
  /// screen owns the in-flight state locally.
  bool _installing = false;

  Future<void> _locate(ExternalTool tool) async {
    final file = await openFile();
    if (file == null) return;
    await widget.controller.locate(tool, file.path);
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    try {
      await widget.controller.installTraceProcessor();
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Tools', style: RadarTypography.appBarTitle),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => unawaited(widget.controller.recheck()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Re-check all'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'External CLI tools the profiling/import flows shell '
                'out to — a Finder-launched app sees a minimal PATH, so '
                'a missing tool is installed or located here rather '
                'than by exporting an environment variable.',
                style: RadarTypography.caption,
              ),
              const SizedBox(height: 16),
              for (final status in widget.controller.statuses) ...[
                _ToolCard(
                  status: status,
                  onLocate: () => unawaited(_locate(status.tool)),
                  showInstall: status.tool == ExternalTool.traceProcessor,
                  installing: _installing,
                  installError: widget.controller.installError,
                  onInstall: _installing ? null : () => unawaited(_install()),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One tool's card: label + purpose, its found/missing status, the
/// Locate/Install actions, and — only while missing — the resolution
/// tiers tried plus a copyable install hint for tools without a
/// one-click installer.
class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.status,
    required this.onLocate,
    required this.showInstall,
    required this.installing,
    required this.installError,
    required this.onInstall,
  });

  final ToolStatus status;
  final VoidCallback onLocate;
  final bool showInstall;
  final bool installing;
  final String? installError;
  final VoidCallback? onInstall;

  @override
  Widget build(BuildContext context) {
    final tool = status.tool;
    final hint = _installHint(tool);

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
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tool.label, style: RadarTypography.monoBody),
            const SizedBox(height: 2),
            Text(tool.purpose, style: RadarTypography.caption),
            const SizedBox(height: 10),
            _StatusLine(status: status),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onLocate,
                  icon: const Icon(Icons.folder_open_outlined, size: 15),
                  label: const Text('Locate…'),
                ),
                if (showInstall)
                  FilledButton.icon(
                    onPressed: onInstall,
                    icon: installing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 15),
                    label: Text(installing ? 'Installing…' : 'Install'),
                  ),
              ],
            ),
            if (showInstall && installError != null) ...[
              const SizedBox(height: 10),
              RadarBanner(
                message: installError!,
                severity: RadarSeverity.critical,
                action: IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  tooltip: 'Copy error',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: installError!)),
                ),
              ),
            ],
            if (!status.found) ...[
              const SizedBox(height: 10),
              Text(_resolutionHint(tool), style: RadarTypography.caption),
              if (hint != null) ...[
                const SizedBox(height: 8),
                _CopyableHint(text: hint),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// `found · <path> · <version>` in accent, or `missing` in amber.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final ToolStatus status;

  @override
  Widget build(BuildContext context) {
    if (!status.found) {
      return Text(
        'missing',
        style: RadarTypography.monoBody.copyWith(
          color: RadarColors.warning,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final path = status.path ?? '?';
    final version = status.version ?? '?';
    return Text(
      'found · $path · $version',
      style: RadarTypography.monoBody.copyWith(color: RadarColors.accent),
    );
  }
}

/// A monospace hint line with a copy-to-clipboard action, for a tool
/// that has no one-click installer (`adb`, the LLVM binaries).
class _CopyableHint extends StatelessWidget {
  const _CopyableHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RadarColors.bgInput,
        borderRadius: RadarDensity.inputRadius,
        border: Border.all(
          color: RadarColors.hairline08,
          width: RadarDensity.hairline,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(text, style: RadarTypography.monoLabel)),
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 14),
              tooltip: 'Copy',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Describes the resolution order [ToolProbe] tried for [tool], so a
/// "missing" status doesn't just say "not found" — it says where it
/// looked, matching the config → env → common-locations → PATH order
/// documented on `ToolProbe.probe`.
String _resolutionHint(ExternalTool tool) {
  final tiers = [
    'a configured path',
    if (tool.envVar.isNotEmpty) '\$${tool.envVar}',
    'common install locations',
    'PATH',
  ];
  return 'Checked: ${tiers.join(' → ')}';
}

/// A copyable install command/pointer for tools without a one-click
/// installer, or null for [ExternalTool.traceProcessor] (which has the
/// Install button instead).
String? _installHint(ExternalTool tool) => switch (tool) {
  ExternalTool.traceProcessor => null,
  ExternalTool.adb => 'brew install android-platform-tools',
  ExternalTool.llvmSymbolizer || ExternalTool.llvmReadelf =>
    'Install the Android NDK (Android Studio → '
        'SDK Manager → SDK Tools → NDK) or `brew install llvm`.',
};
