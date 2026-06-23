// lib/src/ui/leak_radar_screen.dart
import 'package:flutter/material.dart';

import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import '../model/leak_report.dart';
import '../leak_radar.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leak Radar'),
        actions: [
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
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(backgroundColor: _color(finding.severity), radius: 6),
        title: Text(finding.className),
        subtitle: Text(
            '${finding.kind.name} · live ${finding.liveCount} · +${finding.growth}${finding.tag != null ? ' · ${finding.tag}' : ''}'),
        trailing: Text(finding.severity.name),
      );
}
