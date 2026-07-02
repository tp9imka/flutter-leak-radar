import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:radar_ui/radar_ui.dart';

import '../workspace/workspace_controller.dart';

/// The workspace: a multi-select table of loaded dumps, a drag-drop import
/// zone + browse button, a Recent row, and an "analyzing…" bar while a dump is
/// being parsed. Clicking a dump's name opens it in the histogram.
class DumpsScreen extends StatelessWidget {
  const DumpsScreen({
    super.key,
    required this.workspace,
    required this.onOpenHistogram,
  });

  final WorkspaceController workspace;
  final ValueChanged<int> onOpenHistogram;

  static const _types = [
    XTypeGroup(label: 'Heap snapshot', extensions: ['dartheap', 'data']),
  ];

  Future<void> _browse(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: _types);
    if (file == null) return;
    try {
      final bytes = await File(file.path).readAsBytes();
      await workspace.importBytes(
        bytes,
        label: _labelFor(file.path),
        recentPath: file.path,
      );
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Import failed: $e');
    }
  }

  Future<void> _onDrop(BuildContext context, DropDoneDetails details) async {
    for (final f in details.files) {
      try {
        final bytes = await File(f.path).readAsBytes();
        await workspace.importBytes(
          bytes,
          label: _labelFor(f.path),
          recentPath: f.path,
        );
      } catch (e) {
        if (!context.mounted) return;
        _showError(context, 'Import failed: $e');
      }
    }
  }

  static String _labelFor(String path) => path
      .split(Platform.pathSeparator)
      .last
      .replaceAll(RegExp(r'\.(dartheap|data)$'), '');

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        return DropTarget(
          onDragDone: (details) => _onDrop(context, details),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(workspace: workspace, onBrowse: () => _browse(context)),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: _DropHint(),
              ),
              if (workspace.analyzing)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(child: RadarLinearProgress()),
                      const SizedBox(width: 10),
                      Text(
                        'Analyzing ${workspace.analyzingName ?? ''}…',
                        style: RadarTypography.monoLabel,
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: workspace.dumps.isEmpty
                    ? _DropZone(onBrowse: () => _browse(context))
                    : _DumpTable(workspace: workspace, onOpen: onOpenHistogram),
              ),
              if (workspace.recentPaths.isNotEmpty)
                _RecentRow(paths: workspace.recentPaths),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.workspace, required this.onBrowse});
  final WorkspaceController workspace;
  final Future<void> Function() onBrowse;

  @override
  Widget build(BuildContext context) {
    final n = workspace.dumps.length;
    final sel = workspace.trendSelection.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          Text('Workspace', style: RadarTypography.appBarTitle),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'multi-select for diff & trends',
              style: RadarTypography.monoLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '$n dumps · $sel selected',
              style: RadarTypography.monoLabel.copyWith(
                color: RadarColors.text25,
              ),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Open workspace',
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            onPressed: () => workspace.openWorkspace(),
          ),
          IconButton(
            tooltip: 'Save workspace',
            icon: const Icon(Icons.save_outlined, size: 18),
            onPressed: () => workspace.saveWorkspace(),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: () => onBrowse(),
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Import dump'),
          ),
        ],
      ),
    );
  }
}

/// A persistent one-line reminder that the whole screen accepts drag-and-drop
/// import, shown alongside the table once dumps are loaded (the full-size
/// [_DropZone] prompt only renders in the empty state).
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) => Text(
    'Drop .dartheap files anywhere to import',
    style: RadarTypography.monoLabel.copyWith(color: RadarColors.text25),
  );
}

class _DumpTable extends StatelessWidget {
  const _DumpTable({required this.workspace, required this.onOpen});
  final WorkspaceController workspace;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final dumps = workspace.dumps;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: dumps.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final d = dumps[i];
        final checked = workspace.trendSelection.contains(d.id);
        final active = workspace.activeDumpId == d.id;
        return Container(
          decoration: BoxDecoration(
            color: active ? RadarColors.accentSubtle : RadarColors.bgSurface,
            border: Border.all(
              color: active
                  ? RadarColors.accent.withValues(alpha: 0.3)
                  : RadarColors.hairline08,
            ),
            borderRadius: RadarDensity.rowRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: checked,
                onChanged: (_) => workspace.toggleTrendSelection(d.id),
              ),
              Icon(
                d.source == DumpSource.file
                    ? Icons.description_outlined
                    : Icons.adjust,
                size: 16,
                color: d.source == DumpSource.file
                    ? RadarColors.accent
                    : RadarColors.info,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () => onOpen(d.id),
                  child: Text(d.label, style: RadarTypography.monoBody),
                ),
              ),
              Expanded(
                child: Text(d.source.name, style: RadarTypography.monoLabel),
              ),
              Expanded(
                child: Text(
                  _fmtTime(d.capturedAt),
                  style: RadarTypography.monoLabel,
                ),
              ),
              Expanded(
                child: Text(
                  '${d.classCount}',
                  textAlign: TextAlign.right,
                  style: RadarTypography.monoNumber,
                ),
              ),
              Expanded(
                child: Text(
                  _fmtBytes(d.retainedBytes),
                  textAlign: TextAlign.right,
                  style: RadarTypography.monoNumber,
                ),
              ),
              IconButton(
                tooltip: 'Export report',
                icon: const Icon(Icons.download_outlined, size: 16),
                onPressed: () => _exportDump(context, workspace, d.id),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                onPressed: () => workspace.removeDump(d.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onBrowse});
  final Future<void> Function() onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          border: Border.all(color: RadarColors.hairline08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 40,
              color: RadarColors.text10,
            ),
            const SizedBox(height: 10),
            Text('Drop .dartheap files here', style: RadarTypography.monoBody),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => onBrowse(),
              child: Text(
                'browse',
                style: RadarTypography.monoBody.copyWith(
                  color: RadarColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.paths});
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Text(
            'RECENT',
            style: RadarTypography.monoLabel.copyWith(
              color: RadarColors.text10,
            ),
          ),
          for (final p in paths)
            RadarTag(label: p.split(Platform.pathSeparator).last),
        ],
      ),
    );
  }
}

/// Exports [id]'s bundle, surfacing an IO failure (permission, full disk,
/// deleted file) as a [SnackBar] instead of letting it become an unhandled
/// rejection.
Future<void> _exportDump(
  BuildContext context,
  WorkspaceController workspace,
  int id,
) async {
  try {
    await workspace.exportDump(id);
  } catch (e) {
    if (!context.mounted) return;
    _showError(context, 'Export failed: $e');
  }
}

/// Shows a failure [message] via the nearest [ScaffoldMessenger]. No-ops if
/// [context] is no longer mounted (guards the async gap between the failing
/// IO call and this callback) or if no messenger is present (e.g. a widget
/// test that pumps the screen without one).
void _showError(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

String _fmtBytes(int b) {
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '$b B';
}

String _fmtTime(DateTime t) =>
    '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
