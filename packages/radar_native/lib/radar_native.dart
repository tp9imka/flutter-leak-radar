/// Pure-Dart native-heap leak analysis (Lane B: heapprofd still-live accounting).
///
/// Models + analysis for the native memory lane, a peer to `leak_graph`.
/// Exports are added incrementally as each model/analysis lands.
library;

export 'src/analysis/native_diff.dart';
export 'src/model/memory_session.dart';
export 'src/model/native_allocation_diff.dart';
export 'src/model/native_callsite.dart';
export 'src/model/native_frame.dart';
export 'src/model/native_heap_profile.dart';
