import 'package:meta/meta.dart';

import 'leak_finding.dart';
import 'leak_kind.dart';

/// The output of a single [LeakRadar.scan] call.
///
/// Contains all [findings] detected at [capturedAt], the [trigger] label that
/// initiated the scan, the detector [status], and an optional heap-size sample.
@immutable
final class LeakReport {
  const LeakReport({
    required this.findings,
    required this.capturedAt,
    required this.trigger,
    required this.status,
    this.heapBytes,
    this.projectPackageSource = 'none',
  });

  /// All leak findings produced by this scan. Empty when the app is clean.
  final List<LeakFinding> findings;

  /// When the scan completed.
  final DateTime capturedAt;

  /// Human-readable label for what triggered the scan (e.g. `'manual'`,
  /// `'navigation'`, `'periodic'`).
  final String trigger;

  /// Detector status at the time of the scan.
  final LeakRadarStatus status;

  /// Total live heap in bytes at scan time, if available from the VM.
  final int? heapBytes;

  /// Which link of the detection chain resolved the project-package set used to
  /// classify finding origins: `'explicit'` (from config), `'rootLib'` (the
  /// app's root-library package), `'autoDetected'` (derived from the heap), or
  /// `'none'` (no signal). Labels the heuristic so its confidence is honest.
  final String projectPackageSource;

  /// Whether any findings were detected.
  bool get hasLeaks => findings.isNotEmpty;

  /// The highest [LeakSeverity] across all findings; [LeakSeverity.info] when
  /// [findings] is empty.
  LeakSeverity get worstSeverity {
    var worst = LeakSeverity.info;
    for (final f in findings) {
      if (f.severity.index > worst.index) worst = f.severity;
    }
    return worst;
  }

  Map<String, Object?> toJson() => {
    'capturedAt': capturedAt.toIso8601String(),
    'trigger': trigger,
    'status': status.name,
    if (heapBytes != null) 'heapBytes': heapBytes,
    'projectPackageSource': projectPackageSource,
    'findings': findings.map((f) => f.toJson()).toList(),
  };

  String toMarkdown() {
    final heap = heapBytes == null ? 'unmeasured' : '$heapBytes bytes';
    final b = StringBuffer()
      ..writeln('# Leak report ($trigger) — ${capturedAt.toIso8601String()}')
      ..writeln('Status: ${status.name} · findings: ${findings.length}')
      ..writeln('Heap: $heap · project packages: $projectPackageSource')
      ..writeln()
      ..writeln('| Class | Origin | Kind | Severity | Live | Growth | Bytes |')
      ..writeln('|---|---|---|---|---:|---:|---:|');
    for (final f in findings) {
      final bytes = f.bytes?.toString() ?? '—';
      b.writeln(
        '| ${f.className} | ${f.origin.name} | ${f.kind.name} | '
        '${f.severity.name} | ${f.liveCount} | ${f.growth} | $bytes |',
      );
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is LeakReport &&
      other.capturedAt == capturedAt &&
      other.trigger == trigger &&
      other.status == status &&
      other.heapBytes == heapBytes &&
      other.projectPackageSource == projectPackageSource &&
      _listEq(other.findings, findings);

  @override
  int get hashCode => Object.hash(
    capturedAt,
    trigger,
    status,
    heapBytes,
    projectPackageSource,
    Object.hashAll(findings),
  );
}

bool _listEq(List<LeakFinding> a, List<LeakFinding> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
