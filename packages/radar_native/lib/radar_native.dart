/// Pure-Dart native-heap leak analysis (Lane B: heapprofd still-live accounting).
///
/// Models + analysis for the native memory lane, a peer to `leak_graph`.
/// Exports are added incrementally as each model/analysis lands.
library;

export 'src/analysis/native_diff.dart';
export 'src/analysis/native_diff_status.dart';
export 'src/analysis/native_module.dart';
export 'src/analysis/native_module_diff.dart';
export 'src/analysis/native_module_kind.dart';
export 'src/analysis/native_module_summary.dart';
export 'src/analysis/symbol_store.dart';
export 'src/model/ffi_allocation_log.dart';
export 'src/model/memory_session.dart';
export 'src/model/native_allocation_diff.dart';
export 'src/model/native_callsite.dart';
export 'src/model/native_frame.dart';
export 'src/model/native_heap_profile.dart';
export 'src/parse/ffi_allocation_log_parser.dart';
export 'src/parse/native_profile_parser.dart';
export 'src/triage/triage_router.dart';
export 'src/triage/triage_timeline.dart';
