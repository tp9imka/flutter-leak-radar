// test/engine/vm_heap_probe_map_key_test.dart
//
// Task 1.2 — verify safe parentMapKey cast in VmHeapProbe.retainingPath.
// The VM service has historically returned parentMapKey as a plain String
// rather than InstanceRef. The cast must be guarded with an `is` check.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:vm_service/vm_service.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

final _fakeClassRef = ClassRef(id: 'classes/99', name: 'MyMap');

ObjRef _fakeInstance() => InstanceRef(
  id: 'objects/1',
  kind: 'PlainInstance',
  classRef: _fakeClassRef,
);

/// Base fake VmService that returns a single-instance set and a RetainingPath
/// with one element.  Subclasses supply the parentMapKey.
abstract class _FakeVmServiceBase extends Fake implements VmService {
  ObjRef? get fakeParentMapKey;

  @override
  Future<InstanceSet> getInstances(
    String isolateId,
    String classId,
    int limit, {
    bool? includeSubclasses,
    bool? includeImplementers,
    String? idZoneId,
  }) async => InstanceSet()..instances = [_fakeInstance()];

  @override
  Future<RetainingPath> getRetainingPath(
    String isolateId,
    String targetId,
    int limit, {
    String? idZoneId,
  }) async {
    final el = RetainingObject()
      ..value = _fakeInstance()
      ..parentMapKey = fakeParentMapKey;
    return RetainingPath()
      ..gcRootType = 'user-global'
      ..elements = [el];
  }
}

/// Simulates old VM service behavior: parentMapKey is a plain ObjRef that is
/// NOT an InstanceRef (e.g. a base ObjRef), which triggers the unsafe cast
/// to fail if done as `parentMapKey as InstanceRef?`.
class _FakeVmServiceWithStringMapKey extends _FakeVmServiceBase {
  @override
  ObjRef? get fakeParentMapKey =>
      // ObjRef is the base class; it is NOT an InstanceRef, so the old
      // `as InstanceRef?` cast would throw a CastError at runtime.
      ObjRef(id: 'objects/rawKey');
}

/// Simulates correct VM service behavior: parentMapKey is an [InstanceRef].
class _FakeVmServiceWithInstanceRefMapKey extends _FakeVmServiceBase {
  _FakeVmServiceWithInstanceRefMapKey({required this.valueAsString});
  final String valueAsString;

  @override
  ObjRef? get fakeParentMapKey => InstanceRef(
    id: 'objects/key1',
    kind: 'String',
    valueAsString: valueAsString,
    classRef: ClassRef(id: 'classes/dart:core/String', name: 'String'),
  );
}

/// parentMapKey is null.
class _FakeVmServiceWithNullMapKey extends _FakeVmServiceBase {
  @override
  ObjRef? get fakeParentMapKey => null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('VmHeapProbe — safe parentMapKey cast', () {
    test(
      'retainingPath handles non-InstanceRef parentMapKey without throwing',
      () async {
        // Arrange: parentMapKey is a plain String (historical VM behavior).
        final fakeService = _FakeVmServiceWithStringMapKey();
        final probe = VmHeapProbe();
        probe.debugInjectServiceAndCache(
          fakeService,
          isolateId: 'isolates/1',
          classRefCache: {'MyMap': _fakeClassRef},
        );

        // Act: must not throw a CastError.
        final result = await probe.retainingPath('MyMap');

        // Assert: returns a view (not null from a swallowed exception).
        expect(result, isNotNull);
        // mapKey is null when the value is not an InstanceRef.
        expect(result!.elements.first.mapKey, isNull);
      },
    );

    test(
      'retainingPath extracts mapKey when parentMapKey is InstanceRef',
      () async {
        // Arrange: correct VM service behavior.
        final fakeService = _FakeVmServiceWithInstanceRefMapKey(
          valueAsString: 'myKey',
        );
        final probe = VmHeapProbe();
        probe.debugInjectServiceAndCache(
          fakeService,
          isolateId: 'isolates/1',
          classRefCache: {'MyMap': _fakeClassRef},
        );

        final result = await probe.retainingPath('MyMap');

        expect(result!.elements.first.mapKey, 'myKey');
      },
    );

    test('retainingPath handles null parentMapKey without throwing', () async {
      final fakeService = _FakeVmServiceWithNullMapKey();
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        fakeService,
        isolateId: 'isolates/1',
        classRefCache: {'MyMap': _fakeClassRef},
      );

      final result = await probe.retainingPath('MyMap');

      expect(result, isNotNull);
      expect(result!.elements.first.mapKey, isNull);
    });
  });
}
