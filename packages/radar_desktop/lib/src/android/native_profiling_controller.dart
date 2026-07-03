import 'package:flutter/foundation.dart';
import 'package:radar_native/radar_native.dart';

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

/// Owns the offline Android native-profiling workspace: imported heapprofd
/// checkpoints, an optional symbol store to resolve them, and an optional
/// FFI allocation log — the state behind the still-live table, compare, and
/// detail views for Lane B/D analysis.
///
/// Checkpoints are stored raw (never mutated); symbolization is applied on
/// read via [selectedSymbolized] so re-importing a symbol store instantly
/// re-resolves every checkpoint without re-parsing traces.
final class NativeProfilingController extends ChangeNotifier {
  NativeProfilingController(this._importer);

  final NativeTraceImporter _importer;

  List<NativeHeapProfile> _checkpoints = const [];
  SymbolStore? _symbolStore;
  FfiAllocationLog? _ffiLog;
  int _selectedIndex = 0;
  NativeImportState _state = NativeImportState.idle;
  String? _errorMessage;

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
}
