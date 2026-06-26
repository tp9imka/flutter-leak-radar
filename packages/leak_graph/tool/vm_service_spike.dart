// Companion spike — proves the HOST-SIDE VM-service path returns REAL data on a
// physical device. The whole DevTools-extension companion rests on this
// assumption (docs/specs/2026-06-26-companion-devtools-extension-design.md, §6 Q8):
// unlike the in-app self-connect — which DDS refuses on a tethered device — a
// host-side connection (the way DevTools connects) should reach the full VM
// service API. This spike connects from the host and exercises the three things
// the companion needs: getAllocationProfile, a full HeapSnapshotGraph, and
// leak_graph analysis of that snapshot.
//
// HOW TO RUN
//   1. Run the example app on a REAL device in profile mode:
//        cd example && flutter run --profile
//      Copy the VM service URI it prints, e.g.:
//        "A Dart VM Service on ... is available at: http://127.0.0.1:PORT/AbCd=/"
//   2. Point the spike at that URI from this package:
//        cd packages/leak_graph
//        dart run tool/vm_service_spike.dart http://127.0.0.1:PORT/AbCd=/
//
// PASS = non-zero class / object / analysis counts below.
import 'dart:io';

import 'package:leak_graph/leak_graph.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('usage: dart run tool/vm_service_spike.dart <vm-service-uri>');
    stdout.writeln('  <vm-service-uri> = the http(s):// URI `flutter run --profile` prints');
    exitCode = 64;
    return;
  }

  final ws = convertToWebSocketUrl(serviceProtocolUrl: Uri.parse(args.first));
  stdout.writeln('[1/4] Connecting host-side to $ws ...');
  final VmService service = await vmServiceConnectUri(ws.toString());
  final vm = await service.getVM();
  final isolate = (vm.isolates ?? const <IsolateRef>[]).first;
  stdout.writeln('      connected: VM "${vm.name}", isolate "${isolate.name}"');

  // (A) Class histogram — getAllocationProfile is exactly what the in-app
  //     self-connect cannot reach on a real device.
  stdout.writeln('[2/4] getAllocationProfile(gc: true) ...');
  final profile = await service.getAllocationProfile(isolate.id!, gc: true);
  final live = (profile.members ?? <ClassHeapStats>[])
      .where((m) => (m.instancesCurrent ?? 0) > 0)
      .toList()
    ..sort((a, b) => (b.instancesCurrent ?? 0).compareTo(a.instancesCurrent ?? 0));
  stdout.writeln('      ${live.length} live classes; top 5:');
  for (final m in live.take(5)) {
    stdout.writeln('        ${m.instancesCurrent}× ${m.classRef?.name}');
  }

  // (B) Full heap snapshot, pulled over the host connection.
  stdout.writeln('[3/4] HeapSnapshotGraph.getSnapshot (host-side) ...');
  final graph = await HeapSnapshotGraph.getSnapshot(service, isolate);
  stdout.writeln('      ${graph.objects.length} objects, ${graph.classes.length} classes');

  // (C) Run it through leak_graph — the companion's analysis core, unchanged.
  stdout.writeln('[4/4] leak_graph analysis of the live snapshot ...');
  final result = GraphLeakAnalyzer()
      .analyze(VmSnapshotGraphView(graph), const GraphAnalysisOptions());
  stdout.writeln('      scanned ${result.stats.totalObjects} objects '
      '(${result.stats.reachableObjects} reachable); '
      '${result.clusters.length} leak cluster(s)');
  for (final c in result.clusters.take(5)) {
    stdout.writeln('        • ${c.className} ×${c.instanceCount}');
  }

  await service.dispose();

  final passed = live.isNotEmpty && graph.objects.length > 1;
  stdout.writeln('');
  stdout.writeln(passed
      ? 'SPIKE PASSED ✓ — host-side VM APIs returned real data; '
          "the companion's pipeline works on this target."
      : 'SPIKE INCONCLUSIVE ✗ — no data returned; investigate before building the companion.');
}
