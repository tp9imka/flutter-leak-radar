// Gated end-to-end test: connects the REAL VmServiceUriConnection to a running
// VM Service over ws://, proving the desktop connection machinery works against
// a live VM. Skips (passes) unless RADAR_VM_WS is set, so CI stays green.
//
// Run locally against a VM Service you started, e.g.:
//   dart --enable-vm-service=8181 --disable-service-auth-codes keepalive.dart &
//   RADAR_VM_WS=ws://127.0.0.1:8181/ws \
//   flutter test test/integration/real_connect_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/desktop_perf_call.dart';
import 'package:radar_desktop/src/seams/vm_service_uri_connection.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  test(
    'connects to a live VM Service and degrades perf honestly',
    () async {
      final ws = Platform.environment['RADAR_VM_WS'];
      if (ws == null) {
        // ignore: avoid_print
        print('[skip] set RADAR_VM_WS (ws://…/ws) to run this test');
        return;
      }

      final conn = VmServiceUriConnection();
      await conn.connect(ws);

      expect(
        conn.state.phase,
        RadarConnectionPhase.connected,
        reason: conn.lastError ?? 'connect failed',
      );
      expect(conn.vmService, isNotNull);
      expect(conn.isolateRef, isNotNull);
      // ignore: avoid_print
      print(
        '[ok] connected: vm=${conn.state.vmName} isolate=${conn.state.isolateName}',
      );

      // Perf extension is only present if the target embeds flutter_perf_radar.
      // Against a plain VM it should degrade honestly to notAvailable (never fake).
      final perf = PerfDataController(callExtension: perfCallFor(conn));
      await perf.refresh();
      // ignore: avoid_print
      print('[ok] perf loadState = ${perf.loadState}');
      expect(
        perf.loadState,
        anyOf(PerfLoadState.notAvailable, PerfLoadState.loaded),
      );

      await conn.disconnect();
      expect(conn.state.phase, RadarConnectionPhase.disconnected);
      conn.dispose();
      perf.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
