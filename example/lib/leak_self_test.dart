// example/lib/leak_self_test.dart
//
// ON-DEVICE SELF-TEST (no test framework, no extra dependency).
//
// Drives the leak scenario inside the LIVE app — opens + pops LeakyScreen a few
// times so leaked _LeakyScreenState instances accumulate (each retained by its
// live Timer/StreamSubscription), then forces a GC + scan and PRINTS a
// structured summary of every finding grouped by LeakKind to the console.
//
// HOW TO USE
//   flutter run -d <device>        # macOS/emulator => graph + growth work;
//                                  # physical device => precise (notGced) only
//   tap "Run leak self-test"       # on the home screen
//   copy the block fenced between LEAK-RADAR-SUMMARY-BEGIN / -END from the logs
//   and paste it back for diagnosis.
//
// Because it is plain app code it needs no `integration_test` package (and thus
// no androidx.test native dependency), so it runs on any target — including a
// physical Android/iOS device where the integration_test runner cannot.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

import 'leaky_screen.dart';

/// Number of open+pop cycles. >=2 exceeds the graph scan's everyNthNavigation
/// and minClusterSize bars with margin for GC/debounce timing.
const int _kCycles = 6;

/// Opens + pops [LeakyScreen] [_kCycles] times, forces a GC + scan, then prints
/// the leak summary. Pass the app's [NavigatorState] (e.g. `Navigator.of(context)`).
Future<void> runLeakSelfTest(NavigatorState nav) async {
  _print('starting — status=${LeakRadar.status}');
  for (var i = 0; i < _kCycles; i++) {
    // push() completes only when the route is popped, so fire-and-forget then
    // pop it ourselves after it has settled.
    unawaited(
      nav.push(MaterialPageRoute<void>(builder: (_) => const LeakyScreen())),
    );
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (nav.canPop()) nav.pop();
    // Let the debounced navigation scan + every-Nth-nav graph scan run.
    await Future<void>.delayed(const Duration(milliseconds: 750));
    _print('cycle ${i + 1}/$_kCycles done');
  }

  // Let the last in-flight scan settle, then force a deterministic pass.
  await Future<void>.delayed(const Duration(seconds: 1));
  final forced = await LeakRadar.forceGcAndScan();
  _print(
    'forceGcAndScan -> ${forced.findings.length} finding(s), '
    'status=${forced.status}',
  );
  await LeakRadar.graphScanNow();
  await Future<void>.delayed(const Duration(milliseconds: 600));

  _printSummary(LeakRadar.latest ?? forced);
}

void _printSummary(LeakReport report) {
  final byKind = <LeakKind, List<LeakFinding>>{};
  for (final f in report.findings) {
    (byKind[f.kind] ??= <LeakFinding>[]).add(f);
  }

  final b = StringBuffer()
    ..writeln('LEAK-RADAR-SUMMARY-BEGIN')
    ..writeln('status         : ${report.status.name}')
    ..writeln('trigger        : ${report.trigger}')
    ..writeln('total findings : ${report.findings.length}')
    ..writeln('');

  // Print every kind, including empty ones, so the absence of a path
  // (graph/growth) is visible rather than ambiguous.
  for (final kind in LeakKind.values) {
    final group = byKind[kind] ?? const <LeakFinding>[];
    b.writeln('--- ${kind.name} (${group.length}) ---');
    if (group.isEmpty) {
      b.writeln('  (none)');
      continue;
    }
    for (final f in group) {
      b.writeln(
        '  ${f.className}  [${f.severity.name}]  '
        'live=${f.liveCount} growth=${f.growth} '
        'tag=${f.tag ?? "-"} lib=${f.library ?? "?"}',
      );
      final path = f.retainingPath;
      if (path != null) {
        b.writeln('    root: ${path.gcRootType ?? "?"}');
        for (final hop in path.elements.take(8)) {
          b.writeln(
            '      <- ${hop.objectType}'
            '${hop.field != null ? ".${hop.field}" : ""}'
            '${hop.index != null ? "[${hop.index}]" : ""}',
          );
        }
      }
    }
  }
  b.writeln('LEAK-RADAR-SUMMARY-END');
  _print(b.toString());
}

void _print(String line) => debugPrint('[leak-self-test] $line');
