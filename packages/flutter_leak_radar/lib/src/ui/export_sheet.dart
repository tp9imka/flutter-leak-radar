// lib/src/ui/export_sheet.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../leak_radar.dart';
import 'theme/theme.dart';

enum _ExportFormat { json, markdown }

/// Modal bottom sheet for exporting and sharing a [LeakReport].
///
/// Shows a format toggle (JSON / Markdown), a live preview of the
/// export content, and a share button that writes the file and
/// invokes the platform share sheet.
///
/// Show with:
/// ```dart
/// showModalBottomSheet<void>(
///   context: context,
///   backgroundColor: Colors.transparent,
///   barrierColor: const Color.fromRGBO(0, 0, 0, 0.55),
///   isScrollControlled: true,
///   builder: (_) => const LeakExportSheet(),
/// );
/// ```
class LeakExportSheet extends StatefulWidget {
  const LeakExportSheet({super.key});

  @override
  State<LeakExportSheet> createState() => _LeakExportSheetState();
}

class _LeakExportSheetState extends State<LeakExportSheet> {
  _ExportFormat _format = _ExportFormat.markdown;
  bool _sharing = false;

  // ── Computed helpers ──────────────────────────────────────────────────────

  String _previewText() {
    final report = LeakRadar.latest;
    if (report == null) return 'Nothing to export yet';
    if (_format == _ExportFormat.markdown) return report.toMarkdown();
    return const JsonEncoder.withIndent('  ').convert(report.toJson());
  }

  LeakExportFormat get _leakFormat => _format == _ExportFormat.json
      ? LeakExportFormat.json
      : LeakExportFormat.markdown;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _share() async {
    if (LeakRadar.latest == null) return;
    setState(() => _sharing = true);
    try {
      final path = await LeakRadar.exportToFile(format: _leakFormat);
      if (!mounted) return;
      if (path != null) {
        // Static Share API keeps this portable across share_plus 10.x–13.x —
        // consumers pinned to <11 (still on the legacy Share.* API) lack
        // SharePlus.instance/ShareParams.
        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(path)], text: 'Leak Radar report');
      }
    } catch (_) {
      // Never throw into host.
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasReport = LeakRadar.latest != null;
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: LeakRadarColors.cardBg,
          border: Border(
            top: BorderSide(color: Color.fromRGBO(255, 255, 255, 0.10)),
          ),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GrabHandle(),
            const SizedBox(height: 4),
            _Header(),
            const SizedBox(height: 16),
            _FormatToggle(
              selected: _format,
              onChanged: (f) => setState(() => _format = f),
            ),
            const SizedBox(height: 12),
            _PreviewBox(text: _previewText()),
            const SizedBox(height: 16),
            _ShareButton(
              format: _format,
              hasReport: hasReport,
              sharing: _sharing,
              onTap: _share,
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Private sub-widgets ───────────────────────────────────────────────────────

class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Center(
      child: Container(
        width: 38,
        height: 4,
        decoration: BoxDecoration(
          color: const Color.fromRGBO(255, 255, 255, 0.20),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Export findings',
          style: LeakRadarText.metric.copyWith(fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          'Share straight from the device — '
          'into a bug, a PR, a thread.',
          style: monoFont(fontSize: 13, color: LeakRadarColors.text40),
        ),
      ],
    ),
  );
}

class _FormatToggle extends StatelessWidget {
  const _FormatToggle({required this.selected, required this.onChanged});

  final _ExportFormat selected;
  final ValueChanged<_ExportFormat> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: LeakRadarColors.codePreviewBg,
        border: Border.all(color: const Color.fromRGBO(255, 255, 255, 0.10)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _Segment(
            label: 'JSON',
            active: selected == _ExportFormat.json,
            onTap: () => onChanged(_ExportFormat.json),
          ),
          const SizedBox(width: 4),
          _Segment(
            label: 'Markdown',
            active: selected == _ExportFormat.markdown,
            onTap: () => onChanged(_ExportFormat.markdown),
          ),
        ],
      ),
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: active ? LeakRadarColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: monoFont(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: active ? LeakRadarColors.pageBg : LeakRadarColors.text40,
          ),
        ),
      ),
    ),
  );
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Container(
      constraints: const BoxConstraints(maxHeight: 150),
      decoration: BoxDecoration(
        color: LeakRadarColors.codePreviewBg,
        border: Border.all(color: LeakRadarColors.border08),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Text(
          text,
          style: monoFont(
            fontSize: 11.5,
            color: text == 'Nothing to export yet'
                ? LeakRadarColors.text25
                : LeakRadarColors.text60,
          ),
        ),
      ),
    ),
  );
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({
    required this.format,
    required this.hasReport,
    required this.sharing,
    required this.onTap,
  });

  final _ExportFormat format;
  final bool hasReport;
  final bool sharing;
  final VoidCallback onTap;

  String get _label {
    if (!hasReport) return 'Nothing to export yet';
    return format == _ExportFormat.markdown ? 'Share .md' : 'Share .json';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: GestureDetector(
      key: const Key('export_share_btn'),
      onTap: hasReport && !sharing ? onTap : null,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: hasReport ? LeakRadarColors.accent : LeakRadarColors.text25,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (sharing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: LeakRadarColors.pageBg,
                ),
              )
            else ...[
              Icon(
                Icons.upload_outlined,
                size: 18,
                color: LeakRadarColors.pageBg,
              ),
              const SizedBox(width: 8),
              Text(
                _label,
                style: monoFont(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: LeakRadarColors.pageBg,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
