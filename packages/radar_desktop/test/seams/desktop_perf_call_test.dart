import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/seams/desktop_perf_call.dart';
import 'package:radar_workbench/radar_workbench.dart';
import 'package:vm_service/vm_service.dart';

/// Minimal fake covering only the surface [desktopPerfCallExtension]
/// touches. `implements VmService` + a `noSuchMethod` override lets a
/// concrete class stand in for the interface without implementing its full
/// (huge) API — the same recipe used in
/// `test/seams/vm_service_uri_connection_test.dart`.
class _FakeVmService implements VmService {
  _FakeVmService({this.response, this.error});

  final Response? response;
  final Object? error;
  String? lastMethod;
  String? lastIsolateId;

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    lastMethod = method;
    lastIsolateId = isolateId;
    if (error != null) throw error!;
    return response ?? Response();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Minimal fake [RadarConnection]: a plain data holder with fields settable
/// per test, wired through [ChangeNotifier] to satisfy [Listenable].
class _FakeConnection extends ChangeNotifier implements RadarConnection {
  _FakeConnection({this.vmService, this.isolateRef});

  @override
  final VmService? vmService;

  @override
  final IsolateRef? isolateRef;

  @override
  RadarConnectionState get state =>
      const RadarConnectionState(phase: RadarConnectionPhase.connected);
}

const _method = 'ext.perf_radar.snapshot';
final _isolateRef = IsolateRef(id: 'iso-1', name: 'main', number: '1');

void main() {
  group('desktopPerfCallExtension', () {
    test('unwraps the {"result": …} envelope into a decoded map', () async {
      final fake = _FakeVmService(
        response: Response.parse({'result': '{"ok":true,"frames":[]}'}),
      );
      final connection = _FakeConnection(
        vmService: fake,
        isolateRef: _isolateRef,
      );

      final result = await desktopPerfCallExtension(connection, _method);

      expect(result, {'ok': true, 'frames': <Object?>[]});
      expect(fake.lastMethod, _method);
      expect(fake.lastIsolateId, 'iso-1');
    });

    test('maps a -32601 RPCError to ExtensionNotAvailableException', () async {
      final fake = _FakeVmService(
        error: RPCError(_method, -32601, 'Method not found'),
      );
      final connection = _FakeConnection(
        vmService: fake,
        isolateRef: _isolateRef,
      );

      expect(
        () => desktopPerfCallExtension(connection, _method),
        throwsA(isA<ExtensionNotAvailableException>()),
      );
    });

    test(
      'maps a "not found" message to ExtensionNotAvailableException',
      () async {
        final fake = _FakeVmService(
          error: Exception('unknown method $_method'),
        );
        final connection = _FakeConnection(
          vmService: fake,
          isolateRef: _isolateRef,
        );

        expect(
          () => desktopPerfCallExtension(connection, _method),
          throwsA(isA<ExtensionNotAvailableException>()),
        );
      },
    );

    test('a null vmService throws ExtensionNotAvailableException', () async {
      final connection = _FakeConnection(isolateRef: _isolateRef);

      expect(
        () => desktopPerfCallExtension(connection, _method),
        throwsA(isA<ExtensionNotAvailableException>()),
      );
    });

    test('a null isolateRef throws ExtensionNotAvailableException', () async {
      final connection = _FakeConnection(vmService: _FakeVmService());

      expect(
        () => desktopPerfCallExtension(connection, _method),
        throwsA(isA<ExtensionNotAvailableException>()),
      );
    });

    test('rethrows unrelated exceptions unchanged', () async {
      final fake = _FakeVmService(error: Exception('socket reset'));
      final connection = _FakeConnection(
        vmService: fake,
        isolateRef: _isolateRef,
      );

      expect(
        () => desktopPerfCallExtension(connection, _method),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('socket reset'),
          ),
        ),
      );
    });
  });

  group('perfCallFor', () {
    test('binds a connection into a callExtension closure', () async {
      final fake = _FakeVmService(
        response: Response.parse({'result': '{"ok":true}'}),
      );
      final connection = _FakeConnection(
        vmService: fake,
        isolateRef: _isolateRef,
      );

      final callExtension = perfCallFor(connection);
      final result = await callExtension(_method);

      expect(result, {'ok': true});
    });
  });
}
