import 'dart:developer' as developer;

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
  }) : _callExtension = callExtension ?? _notConnected;

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

  /// Default when no host connection is wired: the extension is unavailable, so
  /// [refresh] transitions to [PerfLoadState.notAvailable] without any VM call.
  static Future<Map<String, Object?>> _notConnected(String method) async =>
      throw const ExtensionNotAvailableException();
}

/// Sentinel exception indicating the extension is not registered in the app.
class ExtensionNotAvailableException implements Exception {
  const ExtensionNotAvailableException();

  @override
  String toString() =>
      'ExtensionNotAvailableException: ext.perf_radar.snapshot '
      'is not registered in the connected app.';
}
