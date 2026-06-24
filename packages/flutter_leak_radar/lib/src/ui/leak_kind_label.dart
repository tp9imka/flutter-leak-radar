import '../model/leak_kind.dart';

/// Human-readable labels for [LeakKind] values.
extension LeakKindLabel on LeakKind {
  /// Returns a short, readable description of this kind.
  String get label => switch (this) {
    LeakKind.notDisposed => 'Not disposed',
    LeakKind.notGced => 'Not GCed',
    LeakKind.gcedLate => 'GCed late',
    LeakKind.growth => 'Growth',
    LeakKind.retainedByNonLiveRoot => 'Retained (non-live root)',
  };
}
