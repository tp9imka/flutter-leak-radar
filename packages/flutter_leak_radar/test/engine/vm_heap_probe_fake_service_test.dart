// test/engine/vm_heap_probe_fake_service_test.dart
//
// Unit tests for VmHeapProbe using hand-rolled fake VmService implementations.
// All tests use debugInjectServiceAndCache to bypass VM-service discovery.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:vm_service/vm_service.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

LibraryRef _libRef(String uri) =>
    LibraryRef(id: 'libs/${uri.hashCode}', name: uri, uri: uri);

ClassRef _classRef(String name, {String? libraryUri}) => ClassRef(
  id: 'classes/${name.hashCode}',
  name: name,
  library: libraryUri != null ? _libRef(libraryUri) : null,
);

InstanceRef _instanceRef(String id, String className) =>
    InstanceRef(id: id, kind: 'PlainInstance', classRef: _classRef(className));

/// Returns a fixed root-library URI from getIsolate; getVM/getVersion are not
/// needed because the probe is injected directly.
class _RootLibFakeService extends Fake implements VmService {
  _RootLibFakeService(this._rootLibUri);

  final String? _rootLibUri;

  @override
  Future<Isolate> getIsolate(String isolateId) async =>
      Isolate(rootLib: _rootLibUri == null ? null : _libRef(_rootLibUri));
}

/// Throws from getIsolate, modelling an unreachable RPC on a physical device.
class _ThrowingIsolateFakeService extends Fake implements VmService {
  @override
  Future<Isolate> getIsolate(String isolateId) =>
      Future.error(StateError('unreachable'));
}

// ---------------------------------------------------------------------------
// Fakes — capture group
// ---------------------------------------------------------------------------

/// Returns an AllocationProfile built from the supplied members.
class _ProfileFakeService extends Fake implements VmService {
  _ProfileFakeService(this._members);

  final List<ClassHeapStats> _members;

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async => AllocationProfile()..members = _members;
}

/// Records the `gc` flag passed to getAllocationProfile.
class _GcFlagCaptureFakeService extends Fake implements VmService {
  bool? capturedGc;

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async {
    capturedGc = gc;
    return AllocationProfile()..members = [];
  }
}

/// Always throws the supplied exception from getAllocationProfile.
class _ThrowingProfileFakeService extends Fake implements VmService {
  _ThrowingProfileFakeService(this._error);

  final Object _error;

  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) => Future.error(_error);
}

// ---------------------------------------------------------------------------
// Fakes — retainingPath group
// ---------------------------------------------------------------------------

/// Returns a configurable InstanceSet and RetainingPath.
class _RetainingPathFakeService extends Fake implements VmService {
  _RetainingPathFakeService({
    required this.instances,
    required this.retainingPath,
  });

  final List<ObjRef> instances;
  final RetainingPath retainingPath;

  @override
  Future<InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeSubclasses,
    bool? includeImplementers,
    String? idZoneId,
  }) async => InstanceSet()..instances = instances;

  @override
  Future<RetainingPath> getRetainingPath(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) async => retainingPath;
}

/// Returns an empty instance list (no live instances found).
class _EmptyInstancesFakeService extends Fake implements VmService {
  @override
  Future<InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeSubclasses,
    bool? includeImplementers,
    String? idZoneId,
  }) async => InstanceSet()..instances = [];
}

/// Returns one instance from getInstances but throws SentinelException from
/// getRetainingPath to simulate the object being GC-ed between the two calls.
class _SentinelRetainingPathFakeService extends Fake implements VmService {
  @override
  Future<InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeSubclasses,
    bool? includeImplementers,
    String? idZoneId,
  }) async =>
      InstanceSet()..instances = [_instanceRef('objects/1', 'SomeClass')];

  @override
  Future<RetainingPath> getRetainingPath(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) => Future.error(
    SentinelException.parse('getRetainingPath', {
      'type': 'Sentinel',
      'kind': 'Collected',
      'valueAsString': 'Collected',
    }),
  );
}

/// Returns one instance and a trivial single-hop RetainingPath; used for the
/// throttle test where path content is irrelevant.
class _TrivialRetainingPathFakeService extends Fake implements VmService {
  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async => AllocationProfile()..members = [];

  @override
  Future<InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeSubclasses,
    bool? includeImplementers,
    String? idZoneId,
  }) async => InstanceSet()..instances = [_instanceRef('objects/1', 'Dummy')];

  @override
  Future<RetainingPath> getRetainingPath(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) async {
    final el = RetainingObject()..value = _instanceRef('objects/2', 'Root');
    return RetainingPath()
      ..gcRootType = 'user-global'
      ..elements = [el];
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('capture — parsing and mapping', () {
    test(
      'maps AllocationProfile members to HeapSnapshot.samples correctly',
      () async {
        // Arrange
        final member1 = ClassHeapStats()
          ..classRef = _classRef(
            'HomeBloc',
            libraryUri: 'package:app/blocs/home.dart',
          )
          ..instancesCurrent = 3
          ..bytesCurrent = 128;

        final member2 = ClassHeapStats()
          ..classRef = _classRef(
            'AuthService',
            libraryUri: 'package:app/services/auth.dart',
          )
          ..instancesCurrent = 1
          ..bytesCurrent = 64;

        final probe = VmHeapProbe();
        probe.debugInjectServiceAndCache(
          _ProfileFakeService([member1, member2]),
          isolateId: 'isolates/1',
        );

        // Act
        final snapshot = await probe.capture(forceGc: false);

        // Assert
        expect(snapshot.samples.length, 2);

        final s1 = snapshot.samples[0];
        expect(s1.className, 'HomeBloc');
        expect(s1.library, 'package:app/blocs/home.dart');
        expect(s1.instancesCurrent, 3);
        expect(s1.bytesCurrent, 128);

        final s2 = snapshot.samples[1];
        expect(s2.className, 'AuthService');
        expect(s2.library, 'package:app/services/auth.dart');
        expect(s2.instancesCurrent, 1);
        expect(s2.bytesCurrent, 64);
      },
    );

    test('skips members with null or empty class name', () async {
      // Arrange
      final memberNullRef = ClassHeapStats()
        ..classRef = null
        ..instancesCurrent = 10
        ..bytesCurrent = 512;

      final memberEmptyName = ClassHeapStats()
        ..classRef = ClassRef(id: 'classes/empty', name: '')
        ..instancesCurrent = 2
        ..bytesCurrent = 32;

      final memberValid = ClassHeapStats()
        ..classRef = _classRef('ValidClass')
        ..instancesCurrent = 5
        ..bytesCurrent = 256;

      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _ProfileFakeService([memberNullRef, memberEmptyName, memberValid]),
        isolateId: 'isolates/1',
      );

      // Act
      final snapshot = await probe.capture(forceGc: false);

      // Assert: only the valid member survives the filter
      expect(snapshot.samples.length, 1);
      expect(snapshot.samples.single.className, 'ValidClass');
    });

    test('passes forceGc=true to getAllocationProfile', () async {
      // Arrange
      final fakeService = _GcFlagCaptureFakeService();
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(fakeService, isolateId: 'isolates/1');

      // Act
      await probe.capture(forceGc: true);

      // Assert: the gc flag was forwarded as-is
      expect(fakeService.capturedGc, isTrue);
    });

    test('returns empty snapshot on RPCError (never throws)', () async {
      // Arrange
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _ThrowingProfileFakeService(
          RPCError('getAllocationProfile', -32601, 'test error'),
        ),
        isolateId: 'isolates/1',
      );

      // Act & Assert: must not throw; snapshot is empty
      final snapshot = await probe.capture(forceGc: false);
      expect(snapshot.samples, isEmpty);
    });

    test(
      'returns empty snapshot on generic exception (never throws)',
      () async {
        // Arrange
        final probe = VmHeapProbe();
        probe.debugInjectServiceAndCache(
          _ThrowingProfileFakeService(
            const SocketException('connection reset'),
          ),
          isolateId: 'isolates/1',
        );

        // Act & Assert: must not throw; snapshot is empty
        final snapshot = await probe.capture(forceGc: false);
        expect(snapshot.samples, isEmpty);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('retainingPath — parsing and mapping', () {
    test('builds RetainingPathView from full RetainingPath response', () async {
      // Arrange: two-element retaining path
      final el1 = RetainingObject()
        ..value = InstanceRef(
          id: 'objects/2',
          kind: 'PlainInstance',
          classRef: _classRef('Container'),
        )
        ..parentField = '_child'
        ..parentListIndex = null
        ..parentMapKey = null;

      final el2 = RetainingObject()
        ..value = InstanceRef(
          id: 'objects/3',
          kind: 'Map',
          classRef: _classRef('Map'),
        )
        ..parentField = null
        ..parentListIndex = 0
        ..parentMapKey = null;

      final fakeRetainingPath = RetainingPath()
        ..gcRootType = 'class table'
        ..elements = [el1, el2];

      final fakeService = _RetainingPathFakeService(
        instances: [_instanceRef('objects/1', 'MyClass')],
        retainingPath: fakeRetainingPath,
      );

      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        fakeService,
        isolateId: 'isolates/1',
        classRefCache: {'MyClass': _classRef('MyClass')},
      );

      // Act
      final result = await probe.retainingPath('MyClass');

      // Assert: top-level view
      expect(result, isNotNull);
      expect(result!.gcRootType, 'class table');
      expect(result.elements.length, 2);

      // Assert: first hop — InstanceRef with parentField
      final hop0 = result.elements[0];
      expect(hop0.objectType, 'Container');
      expect(hop0.field, '_child');
      expect(hop0.index, isNull);
      expect(hop0.mapKey, isNull);

      // Assert: second hop — InstanceRef with parentListIndex
      final hop1 = result.elements[1];
      expect(hop1.objectType, 'Map');
      expect(hop1.field, isNull);
      expect(hop1.index, 0);
      expect(hop1.mapKey, isNull);
    });

    test('returns null when getInstances returns empty list', () async {
      // Arrange
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _EmptyInstancesFakeService(),
        isolateId: 'isolates/1',
        classRefCache: {'MyClass': _classRef('MyClass')},
      );

      // Act
      final result = await probe.retainingPath('MyClass');

      // Assert
      expect(result, isNull);
    });

    test('returns null on SentinelException from getRetainingPath', () async {
      // Arrange: object is GC-ed between getInstances and getRetainingPath
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _SentinelRetainingPathFakeService(),
        isolateId: 'isolates/1',
        classRefCache: {'SomeClass': _classRef('SomeClass')},
      );

      // Act & Assert: SentinelException must be swallowed, not re-thrown
      final result = await probe.retainingPath('SomeClass');
      expect(result, isNull);
    });

    test(
      'throttle: returns null after maxRetainingPathRequests in one cycle',
      () async {
        // Arrange: limit is 2; three classes registered in the cache
        final fakeClassRef = _classRef('Shared');
        final probe = VmHeapProbe(maxRetainingPathRequests: 2);
        probe.debugInjectServiceAndCache(
          _TrivialRetainingPathFakeService(),
          isolateId: 'isolates/1',
          classRefCache: {
            'A': fakeClassRef,
            'B': fakeClassRef,
            'C': fakeClassRef,
          },
        );

        // Act: three requests in the same cycle
        final p1 = await probe.retainingPath('A'); // within budget
        final p2 = await probe.retainingPath('B'); // within budget
        final p3 = await probe.retainingPath('C'); // over budget → null

        // Assert
        expect(p1, isNotNull);
        expect(p2, isNotNull);
        expect(p3, isNull);
      },
    );
  });

  group('VmHeapProbe.rootLibraryPackage', () {
    test('extracts the package name from a package: root library', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _RootLibFakeService('package:my_app/main.dart'),
        isolateId: 'isolates/1',
      );
      expect(await probe.rootLibraryPackage(), 'my_app');
    });

    test('returns null for a non-package root library', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _RootLibFakeService('dart:core'),
        isolateId: 'isolates/1',
      );
      expect(await probe.rootLibraryPackage(), isNull);
    });

    test('returns null when the root library is absent', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _RootLibFakeService(null),
        isolateId: 'isolates/1',
      );
      expect(await probe.rootLibraryPackage(), isNull);
    });

    test('returns null (never throws) when the RPC fails', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _ThrowingIsolateFakeService(),
        isolateId: 'isolates/1',
      );
      expect(await probe.rootLibraryPackage(), isNull);
    });
  });
}
