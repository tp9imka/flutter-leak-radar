import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';

/// Seam for turning on-disk native-profiling artifacts into `radar_native`
/// models: heapprofd `.pftrace` checkpoints, symbol-store JSON, and FFI
/// allocation-log JSON. The production implementation wraps
/// `radar_native_host`'s file parsers; tests inject a fake so
/// [NativeProfilingController] can be exercised without a real binary.
abstract interface class NativeTraceImporter {
  /// Parses a heapprofd capture at [path] into a checkpoint labeled [label].
  Future<NativeHeapProfile> importTrace(String path, {required String label});

  /// Parses a symbol-store JSON file at [path].
  Future<SymbolStore> importSymbolStore(String path);

  /// Parses an FFI allocation-log JSON dump at [path].
  Future<FfiAllocationLog> importFfiLog(String path);
}

/// Lifecycle of the most recent import action.
enum NativeImportState {
  /// No import in flight; the last one (if any) finished cleanly.
  idle,

  /// An import is currently awaiting the [NativeTraceImporter].
  loading,

  /// The last import threw; see [NativeProfilingController.errorMessage].
  error,
}

/// Lifecycle of the most recent on-device capture action. Kept separate
/// from [NativeImportState]: a capture spans probing for devices and
/// running heapprofd on the device before an import ever starts, so it
/// needs its own idle/probing/capturing/error states.
enum CaptureState {
  /// No capture or device probe in flight.
  idle,

  /// [NativeProfilingController.refreshDevices] is awaiting [DeviceProbe].
  probing,

  /// [NativeProfilingController.captureAndImport] is awaiting
  /// [NativeHeapCapture].
  capturing,

  /// The last probe or capture failed; see
  /// [NativeProfilingController.captureError].
  error,
}

/// Owns the offline Android native-profiling workspace: imported heapprofd
/// checkpoints, an optional symbol store to resolve them, and an optional
/// FFI allocation log — the state behind the still-live table, compare, and
/// detail views for Lane B/D analysis.
///
/// Checkpoints are stored raw (never mutated); symbolization is applied on
/// read via [selectedSymbolized] so re-importing a symbol store instantly
/// re-resolves every checkpoint without re-parsing traces.
final class NativeProfilingController extends ChangeNotifier {
  NativeProfilingController(
    this._importer, {
    DeviceProbe? deviceProbe,
    NativeHeapCapture? capture,
  }) : _deviceProbe = deviceProbe,
       _capture = capture;

  final NativeTraceImporter _importer;

  /// `null` in builds/environments without on-device capture support
  /// (e.g. no `adb` on this host); see [canCapture].
  final DeviceProbe? _deviceProbe;

  /// `null` alongside [_deviceProbe]; see [canCapture].
  final NativeHeapCapture? _capture;

  List<NativeHeapProfile> _checkpoints = const [];
  SymbolStore? _symbolStore;
  FfiAllocationLog? _ffiLog;
  int _selectedIndex = 0;
  NativeImportState _state = NativeImportState.idle;
  String? _errorMessage;

  List<AndroidDevice> _devices = const [];
  CaptureState _captureState = CaptureState.idle;
  String? _captureError;

  /// A `.pftrace` this small is almost certainly an empty/failed capture
  /// (e.g. wrong package id) rather than a real heap profile.
  static const _minCaptureBytes = 1024;

  /// Imported checkpoints in import order.
  List<NativeHeapProfile> get checkpoints => List.unmodifiable(_checkpoints);

  /// The imported symbol store, if any.
  SymbolStore? get symbolStore => _symbolStore;

  /// The imported FFI allocation log, if any.
  FfiAllocationLog? get ffiLog => _ffiLog;

  /// Index into [checkpoints] backing [selected].
  int get selectedIndex => _selectedIndex;

  /// Lifecycle of the most recent import action.
  NativeImportState get state => _state;

  /// Message from the most recent import failure, or `null`.
  String? get errorMessage => _errorMessage;

  /// True once a non-empty [symbolStore] has been imported.
  bool get isSymbolized => _symbolStore != null && !_symbolStore!.isEmpty;

  /// True when both capture seams were injected, i.e. on-device capture
  /// is available in this build/environment. Callers should gate
  /// capture UI on this rather than calling [refreshDevices] or
  /// [captureAndImport] speculatively.
  bool get canCapture => _deviceProbe != null && _capture != null;

  /// Devices found by the most recent [refreshDevices] call, or `const
  /// []` before the first probe.
  List<AndroidDevice> get devices => List.unmodifiable(_devices);

  /// Lifecycle of the most recent device probe or capture action.
  CaptureState get captureState => _captureState;

  /// Message from the most recent probe or capture failure, or `null`.
  String? get captureError => _captureError;

  /// The raw checkpoint at [selectedIndex], or `null` before any import.
  NativeHeapProfile? get selected =>
      _selectedIndex >= 0 && _selectedIndex < _checkpoints.length
      ? _checkpoints[_selectedIndex]
      : null;

  /// [selected] with [symbolStore] applied, when one is imported. This is
  /// the view every table/detail widget should read.
  NativeHeapProfile? get selectedSymbolized {
    final profile = selected;
    if (profile == null) return null;
    final store = _symbolStore;
    return store != null ? applySymbolStore(profile, store) : profile;
  }

  /// [selectedSymbolized] rolled up by module, or `const []` before any
  /// import.
  List<NativeModuleSummary> get selectedSummaries {
    final profile = selectedSymbolized;
    return profile != null ? summarizeByModule(profile) : const [];
  }

  /// Total still-live bytes of [selectedSymbolized], or `0` before any
  /// import.
  int get selectedTotalStillLiveBytes =>
      selectedSymbolized?.totalStillLiveBytes ?? 0;

  /// Imports the heapprofd trace at [path], appends it to [checkpoints] as
  /// [label], and selects it. Never rethrows: a failure is surfaced via
  /// [state]/[errorMessage] instead.
  Future<void> importTrace(String path, {required String label}) async {
    _beginImport();
    try {
      final profile = await _importer.importTrace(path, label: label);
      _checkpoints = [..._checkpoints, profile];
      _selectedIndex = _checkpoints.length - 1;
      _endImport();
    } catch (error) {
      _failImport(error);
    }
  }

  /// Imports the symbol store at [path]. Applies to every checkpoint via
  /// [selectedSymbolized] — no re-parsing of already-imported traces.
  Future<void> importSymbolStore(String path) async {
    _beginImport();
    try {
      _symbolStore = await _importer.importSymbolStore(path);
      _endImport();
    } catch (error) {
      _failImport(error);
    }
  }

  /// Imports the FFI allocation-log JSON at [path].
  Future<void> importFfiLog(String path) async {
    _beginImport();
    try {
      _ffiLog = await _importer.importFfiLog(path);
      _endImport();
    } catch (error) {
      _failImport(error);
    }
  }

  /// Probes for connected Android devices, populating [devices]. Throws
  /// [StateError] if no [DeviceProbe] was injected — callers should gate
  /// on [canCapture] before offering this in the UI, so hitting this path
  /// means a programmer error, not a runtime condition to swallow.
  Future<void> refreshDevices() async {
    final probe = _deviceProbe;
    if (probe == null) {
      throw StateError('NativeProfilingController has no DeviceProbe');
    }
    _captureState = CaptureState.probing;
    notifyListeners();
    try {
      _devices = await probe.probe();
      _captureState = CaptureState.idle;
      notifyListeners();
    } catch (error) {
      _failCapture(error);
    }
  }

  /// Runs an on-device heapprofd capture per [request], then imports the
  /// resulting trace via [importTrace] and selects it — the one-tap path
  /// from "device plugged in" to "checkpoint on screen". Throws
  /// [StateError] if no [NativeHeapCapture] was injected; see
  /// [refreshDevices] for why that's a throw rather than a no-op.
  Future<void> captureAndImport(CaptureRequest request) async {
    final capture = _capture;
    if (capture == null) {
      throw StateError('NativeProfilingController has no NativeHeapCapture');
    }
    _captureState = CaptureState.capturing;
    _captureError = null;
    notifyListeners();
    try {
      final outputPath =
          '${Directory.systemTemp.createTempSync('radar_capture').path}'
          '/capture.pftrace';
      final path = await capture.capture(request, outputPath: outputPath);
      if (File(path).lengthSync() <= _minCaptureBytes) {
        _captureState = CaptureState.error;
        _captureError =
            'Capture produced no data — is ${request.packageId} installed '
            'and correct?';
        notifyListeners();
        return;
      }
      await importTrace(path, label: request.packageId);
      _captureState = CaptureState.idle;
      notifyListeners();
    } catch (error) {
      _failCapture(error);
    }
  }

  /// Makes [index] the active checkpoint for [selected]/[selectedSummaries].
  /// Out-of-range indexes are ignored.
  void selectCheckpoint(int index) {
    if (index < 0 || index >= _checkpoints.length) return;
    _selectedIndex = index;
    notifyListeners();
  }

  /// Per-module still-live diff between `checkpoints[aIndex]` and
  /// `checkpoints[bIndex]`, symbol-agnostic (raw checkpoints — diffing is
  /// keyed by module, not by symbolized function name).
  List<NativeModuleDiff> diffCheckpoints(int aIndex, int bIndex) =>
      diffModuleSummaries(_checkpoints[aIndex], _checkpoints[bIndex]);

  void _beginImport() {
    _state = NativeImportState.loading;
    _errorMessage = null;
    notifyListeners();
  }

  void _endImport() {
    _state = NativeImportState.idle;
    notifyListeners();
  }

  void _failImport(Object error) {
    _state = NativeImportState.error;
    _errorMessage = error.toString();
    notifyListeners();
  }

  void _failCapture(Object error) {
    _captureState = CaptureState.error;
    _captureError = error.toString();
    notifyListeners();
  }
}
