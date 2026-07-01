import 'dart:convert';
import 'dart:developer' as developer;

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/foundation.dart';

import 'perf_snapshot_dto.dart';

/// Loading state for [PerfDataController].
enum PerfLoadState {
  /// Initial state — no fetch attempted yet.
  idle,

  /// Actively fetching from the extension.
  loading,

  /// Data fetched and available.
  loaded,

  /// The connected app does not expose `ext.perf_radar.snapshot`
  /// (PerfRadar is not initialised in the target app).
  notAvailable,

  /// A network / parse error occurred. [PerfDataController.errorMessage]
  /// contains a human-readable description.
  error,
}

/// Fetches and exposes a [PerfSnapshotDto] from the host app's
/// `ext.perf_radar.snapshot` VM service extension.
///
/// Call [refresh] to (re-)fetch. The controller never throws into
/// its callers — errors set [loadState] to [PerfLoadState.error].
///
/// Inject a [callExtension] override in tests to avoid real VM wiring.
class PerfDataController extends ChangeNotifier {
  PerfDataController({
    Future<Map<String, Object?>> Function(String method)? callExtension,
  }) : _callExtension = callExtension ?? _defaultCallExtension;

  static const _log = 'leakRadarDevTools.perf';
  static const _extensionMethod = 'ext.perf_radar.snapshot';
  static const _resetExtensionMethod = 'ext.perf_radar.resetFrames';

  final Future<Map<String, Object?>> Function(String method) _callExtension;

  PerfLoadState _loadState = PerfLoadState.idle;
  PerfSnapshotDto? _snapshot;
  String? _errorMessage;

  PerfLoadState get loadState => _loadState;
  PerfSnapshotDto? get snapshot => _snapshot;
  String? get errorMessage => _errorMessage;

  /// Fetches a fresh snapshot from the connected app.
  ///
  /// No-ops while already loading. Safe to call multiple times.
  Future<void> refresh() async {
    if (_loadState == PerfLoadState.loading) return;
    _loadState = PerfLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final raw = await _callExtension(_extensionMethod);
      final dto = PerfSnapshotDto.tryFromJson(raw, logName: _log);
      if (dto == null) {
        _loadState = PerfLoadState.error;
        _errorMessage = 'Failed to parse snapshot response.';
      } else {
        _snapshot = dto;
        _loadState = PerfLoadState.loaded;
      }
    } on ExtensionNotAvailableException {
      developer.log(
        '$_extensionMethod not available in connected app',
        name: _log,
      );
      _loadState = PerfLoadState.notAvailable;
    } catch (e, s) {
      developer.log('refresh failed: $e', name: _log, error: e, stackTrace: s);
      _loadState = PerfLoadState.error;
      _errorMessage = e.toString();
    }

    notifyListeners();
  }

  /// Resets the connected app's frame counters via
  /// `ext.perf_radar.resetFrames`, then re-fetches so the view reflects
  /// the fresh (zeroed) measurement window.
  ///
  /// Never throws — when the connected app is unavailable or the
  /// extension isn't registered, this logs and returns without touching
  /// [loadState], leaving the last-known snapshot displayed.
  Future<void> resetFrames() async {
    try {
      await _callExtension(_resetExtensionMethod);
    } on ExtensionNotAvailableException {
      developer.log(
        '$_resetExtensionMethod not available in connected app',
        name: _log,
      );
      return;
    } catch (e, s) {
      developer.log(
        'resetFrames failed: $e',
        name: _log,
        error: e,
        stackTrace: s,
      );
      return;
    }
    await refresh();
  }

  /// Default implementation calls [serviceManager]'s callServiceExtensionOnMainIsolate.
  static Future<Map<String, Object?>> _defaultCallExtension(
    String method,
  ) async {
    final svc = serviceManager.service;
    if (svc == null) throw const ExtensionNotAvailableException();
    final isolateId = serviceManager.isolateManager.mainIsolate.value?.id;
    if (isolateId == null) throw const ExtensionNotAvailableException();

    try {
      final response = await svc.callServiceExtension(
        method,
        isolateId: isolateId,
      );
      // The result is in response.json, keyed by the extension result fields.
      final json = response.json;
      if (json == null) {
        throw StateError('Extension returned null JSON for $method');
      }
      // The extension wraps in {"result": ...} via ServiceExtensionResponse.
      // When the VM protocol delivers it through callServiceExtension the
      // payload is already unwrapped into the top-level map; however the
      // result field may carry the JSON string that was passed to
      // ServiceExtensionResponse.result().  Handle both shapes.
      final result = json['result'];
      if (result is String) {
        final decoded = jsonDecode(result);
        if (decoded is Map<String, Object?>) return decoded;
        // Some VM versions nest the string differently; try top-level.
        return json.cast<String, Object?>();
      }
      return json.cast<String, Object?>();
    } on Exception catch (e) {
      // RPCError with code -32601 means method not found → not available.
      if (e.toString().contains('-32601') ||
          e.toString().toLowerCase().contains('not found') ||
          e.toString().toLowerCase().contains('unknown method')) {
        throw const ExtensionNotAvailableException();
      }
      rethrow;
    }
  }
}

/// Sentinel exception indicating the extension is not registered in the app.
class ExtensionNotAvailableException implements Exception {
  const ExtensionNotAvailableException();

  @override
  String toString() =>
      'ExtensionNotAvailableException: ext.perf_radar.snapshot '
      'is not registered in the connected app.';
}
