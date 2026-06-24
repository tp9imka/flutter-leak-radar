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

  /// Replaces the old permanent `_connectFailed` bool.
  /// Null means "no failure recorded"; non-null means "don't retry before this
  /// instant". A successful connect resets this to null.
  DateTime? _nextRetryAllowedAt;

  static const Duration _reconnectBackoff = Duration(seconds: 30);

  /// Optional test seam: when set, [_ensureConnected] calls this instead of
  /// the real [vmServiceConnectUri] path.
  Future<VmService> Function()? _connectionFactory;

  /// Cache of class name → [ClassRef] populated during [capture].
  /// Used by [retainingPath] to avoid a redundant [getAllocationProfile] call.
  /// MUST be cleared whenever the VM-service connection is dropped, because
  /// [ClassRef.id] values become stale after a reconnect.
  final Map<String, ClassRef> _classRefCache = <String, ClassRef>{};

  Future<Uri?> _serviceUri() async {
    var uri = (await developer.Service.getInfo()).serverWebSocketUri;
    if (uri != null) return uri;
    uri = (await developer.Service.controlWebServer(
      enable: true,
    )).serverWebSocketUri;
    return uri;
  }

  Future<VmService?> _ensureConnected() async {
    if (_service != null) return _service;

    // Back-off guard: don't hammer the VM service after a recent failure.
    final retryAt = _nextRetryAllowedAt;
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return null;

    try {
      VmService service;
      if (_connectionFactory != null) {
        // Test-injected factory: skip URI discovery and socket validation.
        service = await _connectionFactory!();
        // Resolve isolate id via developer.Service only (avoids a getVM() RPC
        // that test fakes don't need to implement).
        _isolateId =
            developer.Service.getIsolateId(dart_isolate.Isolate.current) ??
            'isolates/test';
      } else {
        final uri = await _serviceUri();
        if (uri == null) {
          // No VM service URI available (e.g. running in release mode or the
          // service hasn't started yet). Apply the full 30 s back-off to avoid
          // hammering Service.getInfo on every capture tick.
          // Contrast: a mid-capture socket drop (the catch block in [capture])
          // resets _nextRetryAllowedAt to null, allowing an immediate retry on
          // the next capture cycle — because the service was reachable moments
          // ago and a transient disconnect is expected to resolve quickly.
          _nextRetryAllowedAt = DateTime.now().add(_reconnectBackoff);
          return null;
        }
        service = await vmServiceConnectUri(uri.toString());
        await service.getVersion(); // validate socket
        _isolateId =
            developer.Service.getIsolateId(dart_isolate.Isolate.current) ??
            (await service.getVM()).isolates?.first.id;
      }
      _service = service;
      _nextRetryAllowedAt = null; // clear on success
      return service;
    } catch (e) {
      _logger.log('VmHeapProbe connect failed: $e', level: LeakLogLevel.error);
      _nextRetryAllowedAt = DateTime.now().add(_reconnectBackoff);
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
      _service = null; // drop connection; force reconnect next time
      _classRefCache.clear(); // ids are stale after reconnect
      _nextRetryAllowedAt = null; // allow immediate retry on next capture
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
      final targetId = instanceSet.instances?.isNotEmpty == true
          ? instanceSet.instances!.first.id
          : null;
      if (targetId == null) return null;

      final path = await service.getRetainingPath(isolateId, targetId, 100000);
      final hops = <RetainingHop>[];
      for (final el in path.elements ?? const <RetainingObject>[]) {
        final value = el.value;
        final type = value is InstanceRef
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
    _nextRetryAllowedAt = null; // clear any backoff when injecting directly
    if (classRefCache != null) {
      _classRefCache
        ..clear()
        ..addAll(classRefCache);
    }
  }

  /// Test seam: replace the real [vmServiceConnectUri] code path with a
  /// custom factory. Set to null to restore default behaviour.
  @visibleForTesting
  void debugInjectConnectionFactory(Future<VmService> Function()? factory) {
    _connectionFactory = factory;
    _service = null; // ensure _ensureConnected will call the factory
    _isolateId = null;
    _nextRetryAllowedAt = null;
  }

  /// Test seam: override [_nextRetryAllowedAt] so tests can bypass the 30 s
  /// backoff without sleeping.
  @visibleForTesting
  void debugOverrideNextRetryAllowedAt(DateTime? value) {
    _nextRetryAllowedAt = value;
  }

  /// Test seam: read-only view of the internal class-ref cache.
  @visibleForTesting
  Map<String, ClassRef> get debugClassRefCache =>
      Map<String, ClassRef>.unmodifiable(_classRefCache);
}
