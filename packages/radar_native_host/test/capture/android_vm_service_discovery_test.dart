import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

const _sampleLogcatLine =
    '07-04 10:15:23.456  1234  1234 I flutter : The Dart VM service is '
    'listening on http://127.0.0.1:43219/GJur1BL3JL4=/\n';

const _observatoryLogcatLine =
    '07-04 09:00:00.000  1234  1234 I flutter : Observatory listening on '
    'http://127.0.0.1:8100/AbCdEf12=/\n';

const _noiseOnlyLogcat =
    '07-04 10:15:20.000  1234  1234 I flutter : Some unrelated line\n'
    '07-04 10:15:21.000  1234  1234 D ActivityManager: noise\n';

class _AdbCall {
  const _AdbCall(this.args, this.serial);

  final List<String> args;
  final String? serial;
}

class _FakeAdbRunner implements AdbRunner {
  _FakeAdbRunner({this.logcatOutput = '', this.forwardOutput = ''});

  final String logcatOutput;
  final String forwardOutput;
  final calls = <_AdbCall>[];

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    calls.add(_AdbCall(args, serial));
    if (args case ['logcat', '-d']) {
      return AdbResult(0, logcatOutput, '');
    }
    if (args case ['forward', 'tcp:0', _]) {
      return AdbResult(0, forwardOutput, '');
    }
    return AdbResult(1, '', 'unexpected call: $args');
  }
}

void main() {
  group('parseLogcatVmServiceUris', () {
    test('parses a real Dart VM service line', () {
      final uris = parseLogcatVmServiceUris(_sampleLogcatLine);

      expect(uris, hasLength(1));
      expect(uris.single.host, '127.0.0.1');
      expect(uris.single.port, 43219);
      expect(uris.single.path, '/GJur1BL3JL4=/');
    });

    test('parses two lines, preserving first-to-last order', () {
      const logcat =
          'The Dart VM service is listening on http://127.0.0.1:1111/aaa=/\n'
          'The Dart VM service is listening on http://127.0.0.1:2222/bbb=/\n';

      final uris = parseLogcatVmServiceUris(logcat);

      expect(uris, hasLength(2));
      expect(uris[0].port, 1111);
      expect(uris[0].path, '/aaa=/');
      expect(uris[1].port, 2222);
      expect(uris[1].path, '/bbb=/');
    });

    test('parses the legacy Observatory variant', () {
      final uris = parseLogcatVmServiceUris(_observatoryLogcatLine);

      expect(uris, hasLength(1));
      expect(uris.single.host, '127.0.0.1');
      expect(uris.single.port, 8100);
      expect(uris.single.path, '/AbCdEf12=/');
    });

    test('returns an empty list when logcat has no VM-service line', () {
      expect(parseLogcatVmServiceUris(_noiseOnlyLogcat), isEmpty);
    });
  });

  group('AndroidVmServiceDiscovery.scan', () {
    test(
      'runs adb logcat -d, parses it, and passes the serial through',
      () async {
        final runner = _FakeAdbRunner(logcatOutput: _sampleLogcatLine);
        final discovery = AndroidVmServiceDiscovery(runner);

        final uris = await discovery.scan(serial: 'SERIAL1');

        expect(uris, hasLength(1));
        expect(uris.single.port, 43219);
        expect(runner.calls.single.args, ['logcat', '-d']);
        expect(runner.calls.single.serial, 'SERIAL1');
      },
    );
  });

  group('AndroidVmServiceDiscovery.forward', () {
    test('parses the assigned host port from stdout', () async {
      final runner = _FakeAdbRunner(forwardOutput: '54321\n');
      final discovery = AndroidVmServiceDiscovery(runner);

      final hostPort = await discovery.forward(43219, serial: 'SERIAL1');

      expect(hostPort, 54321);
      expect(runner.calls.single.args, ['forward', 'tcp:0', 'tcp:43219']);
      expect(runner.calls.single.serial, 'SERIAL1');
    });

    test('throws a clear error when adb does not print a port', () async {
      final runner = _FakeAdbRunner(forwardOutput: 'not a port\n');
      final discovery = AndroidVmServiceDiscovery(runner);

      expect(() => discovery.forward(43219), throwsStateError);
    });
  });

  group('AndroidVmServiceDiscovery.discoverWsUri', () {
    test(
      'uses the newest match, forwards it, and builds a ws:// URI',
      () async {
        const logcat =
            'The Dart VM service is listening on http://127.0.0.1:1111/old=/\n'
            'The Dart VM service is listening on '
            'http://127.0.0.1:43219/GJur1BL3JL4=/\n';
        final runner = _FakeAdbRunner(
          logcatOutput: logcat,
          forwardOutput: '54321\n',
        );
        final discovery = AndroidVmServiceDiscovery(runner);

        final uri = await discovery.discoverWsUri();

        expect(uri, 'ws://127.0.0.1:54321/GJur1BL3JL4=/ws');
        final forwardCall = runner.calls.firstWhere(
          (c) => c.args.first == 'forward',
        );
        expect(forwardCall.args, ['forward', 'tcp:0', 'tcp:43219']);
      },
    );

    test('returns null when scan finds nothing', () async {
      final runner = _FakeAdbRunner(logcatOutput: _noiseOnlyLogcat);
      final discovery = AndroidVmServiceDiscovery(runner);

      expect(await discovery.discoverWsUri(), isNull);
    });
  });
}
