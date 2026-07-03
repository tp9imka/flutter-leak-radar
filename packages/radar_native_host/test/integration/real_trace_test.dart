import 'dart:io';

import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

void main() {
  test('parses a real .pftrace into a non-empty checkpoint', () async {
    final bin = Platform.environment['RADAR_TP_BIN'];
    final trace = Platform.environment['RADAR_TP_TRACE'];
    if (bin == null || trace == null) {
      print('[skip] set RADAR_TP_BIN and RADAR_TP_TRACE to run this test');
      return;
    }
    final parser = PerfettoTraceProcessorParser(
      ProcessTraceProcessorRunner(binaryPath: bin),
    );
    final p = await parser.parseTrace(
      trace,
      capturedAt: DateTime.now(),
      label: 'real',
    );
    expect(p.callsites, isNotEmpty);
    expect(p.totalStillLiveBytes, greaterThan(0));
    // leaf frame of the top callsite is an allocator in libc
    final top =
        (p.callsites.toList()
              ..sort((a, b) => b.stillLiveBytes.compareTo(a.stillLiveBytes)))
            .first;
    expect(top.frames.first.module, contains('libc.so'));
  });
}
