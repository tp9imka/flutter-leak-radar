import 'dart:async';

import 'package:radar_ci/radar_ci.dart';
import 'package:test/test.dart';

void main() {
  group('toWebSocketUri', () {
    test('rewrites http to ws and appends /ws', () {
      expect(
        toWebSocketUri('http://127.0.0.1:8181/abcd123=/'),
        'ws://127.0.0.1:8181/abcd123=/ws',
      );
    });

    test('rewrites https to wss', () {
      expect(
        toWebSocketUri('https://127.0.0.1:8181/t=/'),
        startsWith('wss://'),
      );
    });

    test('leaves an already-ws /ws URI unchanged', () {
      expect(
        toWebSocketUri('ws://127.0.0.1:8181/t=/ws'),
        'ws://127.0.0.1:8181/t=/ws',
      );
    });
  });

  group('vmServiceWsUriFromMachineLine (flutter --machine)', () {
    test('extracts wsUri from an app.debugPort event', () {
      const line =
          '[{"event":"app.debugPort","params":{"appId":"x","port":63722,'
          '"wsUri":"ws://127.0.0.1:63722/AbC=/ws"}}]';
      expect(
        vmServiceWsUriFromMachineLine(line),
        'ws://127.0.0.1:63722/AbC=/ws',
      );
    });

    test('normalises a bare wsUri missing its /ws suffix', () {
      const line =
          '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:1/T=/"}}]';
      expect(vmServiceWsUriFromMachineLine(line), 'ws://127.0.0.1:1/T=/ws');
    });

    test('ignores unrelated daemon events', () {
      expect(
        vmServiceWsUriFromMachineLine(
          '[{"event":"app.started","params":{"appId":"x"}}]',
        ),
        isNull,
      );
    });

    test('ignores non-JSON stdout noise', () {
      expect(vmServiceWsUriFromMachineLine('Launching lib/main.dart…'), isNull);
    });
  });

  group('discoverVmServiceWsUri — plain-dart / logcat fallback', () {
    test('parses the "Dart VM service is listening on" stdout line', () {
      // Identical wording to the adb-logcat line, so radar_native_host's
      // parseLogcatVmServiceUris matches plain `dart --enable-vm-service` too.
      const line =
          'The Dart VM service is listening on http://127.0.0.1:8181/Xy9=/';
      expect(discoverVmServiceWsUri(line), 'ws://127.0.0.1:8181/Xy9=/ws');
    });

    test('tolerates the legacy Observatory wording', () {
      const line = 'Observatory listening on http://127.0.0.1:8182/Q=/';
      expect(discoverVmServiceWsUri(line), 'ws://127.0.0.1:8182/Q=/ws');
    });

    test('prefers a machine-JSON wsUri when present', () {
      const line =
          '[{"event":"app.debugPort","params":{"wsUri":"ws://127.0.0.1:5/M=/ws"}}]';
      expect(discoverVmServiceWsUri(line), 'ws://127.0.0.1:5/M=/ws');
    });

    test('returns null for an unrelated line', () {
      expect(discoverVmServiceWsUri('flutter: hello world'), isNull);
    });
  });

  group('scanForVmServiceUri', () {
    test('completes with the first discovered URI', () async {
      final controller = StreamController<String>();
      final found = scanForVmServiceUri(
        controller.stream,
        timeout: const Duration(seconds: 5),
      );
      controller.add('Launching…');
      controller.add(
        'The Dart VM service is listening on http://127.0.0.1:9000/K=/',
      );
      controller.add('… more output');
      await controller.close();

      expect(await found, 'ws://127.0.0.1:9000/K=/ws');
    });

    test('returns null when the stream ends without a match', () async {
      final found = scanForVmServiceUri(
        Stream.fromIterable(['no', 'uri', 'here']),
        timeout: const Duration(seconds: 5),
      );
      expect(await found, isNull);
    });
  });
}
