// lib/src/ui/leak_radar_screen.dart
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';
import 'growth_sparkline.dart';
import 'retaining_path_tile.dart';

/// Minimal results screen: findings list + "Scan now". Push it from anywhere:
/// `Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeakRadarScreen()));`
class LeakRadarScreen extends StatefulWidget {
  const LeakRadarScreen({super.key});

  @override
  State<LeakRadarScreen> createState() => _LeakRadarScreenState();
}

class _LeakRadarScreenState extends State<LeakRadarScreen> {
  LeakReport? _report;
  bool _scanning = false;

  /// Cached path from the most recent [_export] call, reused by [_share]
  /// so we never write a second temp file for the same report.
  String? _lastExportPath;

  @override
  void initState() {
    super.initState();
    _report = LeakRadar.latest;
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final report = await LeakRadar.scan();
    if (!mounted) return;
    setState(() {
      _report = report;
      _scanning = false;
      _lastExportPath = null; // invalidate cached path after a new scan
    });
  }

  /// Writes the report to a temp file and caches the path for [_share].
  Future<String?> _getOrExportPath() =>
      LeakRadar.exportToFile(format: LeakExportFormat.markdown);

  Future<void> _export() async {
    final path = await _getOrExportPath();
    if (!mounted) return;
    if (path != null) _lastExportPath = path;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path != null ? 'Exported: $path' : 'Export failed'),
      ),
    );
  }

  /// Reuses [_lastExportPath] if available so Share doesn't write a second
  /// temp file when the user already pressed Export for this scan.
  Future<void> _share() async {
    try {
      final path = _lastExportPath ?? await _getOrExportPath();
      if (!mounted || path == null) return;
      _lastExportPath = path;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: 'Leak Radar report'),
      );
    } catch (_) {
      // Never throw into host — swallow share errors silently.
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leak Radar'),
        actions: [
          IconButton(
            tooltip: 'Export',
            icon: const Icon(Icons.download),
            onPressed: _scanning ? null : _export,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share),
            onPressed: _scanning ? null : _share,
          ),
          IconButton(
            tooltip: 'Scan now',
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            onPressed: _scanning ? null : _scan,
          ),
        ],
      ),
      body: report == null || report.findings.isEmpty
          ? _EmptyState(status: report?.status ?? LeakRadar.status)
          : ListView.builder(
              itemCount: report.findings.length,
              itemBuilder: (_, i) => _FindingTile(finding: report.findings[i]),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.status});
  final LeakRadarStatus status;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified, size: 48),
            const SizedBox(height: 8),
            const Text('No leaks detected'),
            const SizedBox(height: 4),
            Text('status: ${status.name}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding});

  final LeakFinding finding;

  Color _color(LeakSeverity s) => switch (s) {
        LeakSeverity.critical => Colors.red,
        LeakSeverity.warning => Colors.orange,
        LeakSeverity.info => Colors.blue,
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: _color(finding.severity),
              radius: 8,
            ),
            title: Text(finding.className),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${finding.kind.name} · live ${finding.liveCount} · '
                  '+${finding.growth}'
                  '${finding.tag != null ? ' · ${finding.tag}' : ''}',
                ),
                const SizedBox(height: 4),
                GrowthSparkline(series: finding.series),
              ],
            ),
            // Fixed-width trailing avoids RenderFlex overflow on narrow tiles
            // (ListTile gives trailing a tight constraint; a bare Column + wide
            // sparkline would overflow at 320 px screen widths).
            trailing: SizedBox(
              width: 56,
              child: Text(
                finding.severity.name,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          // Precise findings (notGced / notDisposed) carry no heap-sample
          // series, so the gate below intentionally hides the retaining-path
          // tile for them. Those findings come from the object registry, not
          // from heap-snapshot growth, and their retaining path is already
          // implicit in the lifecycle violation. No behavior change needed.
          if (finding.series.isNotEmpty)
            RetainingPathTile(
              className: finding.className,
              onFetch: () => LeakRadar.fetchRetainingPath(
                finding.className,
              ),
            ),
        ],
      ),
    );
  }
}
