// lib/src/engine/vm_heap_probe.dart
import 'dart:developer' as developer;
import 'dart:isolate' as dart_isolate;

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../model/retaining_path.dart';
import '../util/rate_limited_logger.dart';
import 'class_sample.dart';
import 'heap_probe.dart';

/// The sole unit that imports `package:vm_service`. Connects to the running
/// app's own VM service (debug/profile) and never throws into callers.
class VmHeapProbe implements HeapProbe {
  VmHeapProbe({RateLimitedLogger? logger, this.maxRetainingPathRequests = 5})
      : _logger = logger ?? RateLimitedLogger();

  final RateLimitedLogger _logger;
  final int maxRetainingPathRequests;

  int _pathRequestsThisCycle = 0;

  VmService? _service;
  String? _isolateId;
  bool _connectFailed = false;

  /// Cache of class name → [ClassRef] populated during [capture].
  /// Used by [retainingPath] to avoid a redundant [getAllocationProfile] call.
  final Map<String, ClassRef> _classRefCache = <String, ClassRef>{};

  Future<Uri?> _serviceUri() async {
    var uri = (await developer.Service.getInfo()).serverWebSocketUri;
    if (uri != null) return uri;
    uri =
        (await developer.Service.controlWebServer(enable: true))
            .serverWebSocketUri;
    return uri;
  }

  Future<VmService?> _ensureConnected() async {
    if (_service != null) return _service;
    if (_connectFailed) return null;
    try {
      final uri = await _serviceUri();
      if (uri == null) {
        _connectFailed = true;
        return null;
      }
      final service = await vmServiceConnectUri(uri.toString());
      await service.getVersion(); // validate socket
      _isolateId =
          developer.Service.getIsolateId(dart_isolate.Isolate.current) ??
          (await service.getVM()).isolates?.first.id;
      _service = service;
      return service;
    } catch (e) {
      _logger.log(
        'VmHeapProbe connect failed: $e',
        level: LeakLogLevel.error,
      );
      _connectFailed = true;
      return null;
    }
  }

  @override
  Future<bool> get isAvailable async {
    try {
      final info = await developer.Service.getInfo();
      if (info.serverWebSocketUri != null) return true;
      final started = await developer.Service.controlWebServer(enable: true);
      return started.serverWebSocketUri != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async {
    _pathRequestsThisCycle = 0; // reset throttle budget each cycle
    final service = await _ensureConnected();
    final isolateId = _isolateId;
    if (service == null || isolateId == null) {
      return HeapSnapshot(
        samples: const <ClassSample>[],
        capturedAt: DateTime.now(),
      );
    }
    try {
      final profile = await service.getAllocationProfile(
        isolateId,
        gc: forceGc,
      );
      final now = DateTime.now();
      final samples = <ClassSample>[];
      for (final m in profile.members ?? const <ClassHeapStats>[]) {
        final name = m.classRef?.name;
        if (name == null || name.isEmpty) continue;
        if (m.classRef != null) _classRefCache[name] = m.classRef!;
        samples.add(
          ClassSample(
            className: name,
            library: m.classRef?.library?.uri,
            instancesCurrent: m.instancesCurrent ?? 0,
            bytesCurrent: m.bytesCurrent ?? 0,
            timestamp: now,
          ),
        );
      }
      return HeapSnapshot(samples: samples, capturedAt: now);
    } on RPCError catch (e) {
      _logger.log(
        'getAllocationProfile RPCError: ${e.message}',
        level: LeakLogLevel.error,
      );
      return HeapSnapshot(
        samples: const <ClassSample>[],
        capturedAt: DateTime.now(),
      );
    } catch (e) {
      _logger.log('capture failed: $e', level: LeakLogLevel.error);
      _service = null; // force reconnect next time
      return HeapSnapshot(
        samples: const <ClassSample>[],
        capturedAt: DateTime.now(),
      );
    }
  }

  @override
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances = 10,
  }) async {
    if (_pathRequestsThisCycle >= maxRetainingPathRequests) {
      _logger.log(
        'retainingPath throttled: $maxRetainingPathRequests per-cycle limit reached',
        level: LeakLogLevel.verbose,
      );
      return null;
    }
    _pathRequestsThisCycle++;
    final service = await _ensureConnected();
    final isolateId = _isolateId;
    if (service == null || isolateId == null) return null;
    try {
      // Cache lookup first — avoids a full getAllocationProfile per expand.
      String? classId = _classRefCache[className]?.id;
      if (classId == null) {
        // Cold path: fall back to a fresh profile (e.g. first retainingPath
        // before any capture has run).
        final profile = await service.getAllocationProfile(isolateId);
        for (final m in profile.members ?? const <ClassHeapStats>[]) {
          final name = m.classRef?.name;
          if (name != null && m.classRef != null) {
            _classRefCache[name] = m.classRef!;
          }
        }
        classId = _classRefCache[className]?.id;
      }
      if (classId == null) return null;

      final instanceSet = await service.getInstances(
        isolateId,
        classId,
        maxInstances,
      );
      final targetId =
          instanceSet.instances?.isNotEmpty == true
              ? instanceSet.instances!.first.id
              : null;
      if (targetId == null) return null;

      final path = await service.getRetainingPath(isolateId, targetId, 100000);
      final hops = <RetainingHop>[];
      for (final el in path.elements ?? const <RetainingObject>[]) {
        final value = el.value;
        final type =
            value is InstanceRef
                ? (value.classRef?.name ?? value.kind ?? 'Object')
                : (value?.runtimeType.toString() ?? 'Object');
        hops.add(
          RetainingHop(
            objectType: type,
            field: el.parentField?.toString(),
            index: el.parentListIndex,
            mapKey: el.parentMapKey is InstanceRef
                ? (el.parentMapKey as InstanceRef).valueAsString
                : null,
          ),
        );
      }
      return RetainingPathView(gcRootType: path.gcRootType, elements: hops);
    } on SentinelException {
      return null; // object GCed between selection and the path RPC
    } catch (e) {
      _logger.log('retainingPath failed: $e', level: LeakLogLevel.error);
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _service?.dispose();
    } catch (_) {}
    _service = null;
    _classRefCache.clear();
  }

  /// Test seam: inject a pre-wired [VmService] and optional cache entries
  /// without going through the real VM service discovery path.
  @visibleForTesting
  void debugInjectServiceAndCache(
    VmService service, {
    required String isolateId,
    Map<String, ClassRef>? classRefCache,
  }) {
    _service = service;
    _isolateId = isolateId;
    if (classRefCache != null) _classRefCache.addAll(classRefCache);
  }
}
