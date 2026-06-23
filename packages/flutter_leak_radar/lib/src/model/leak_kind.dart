/// Mirrors package:leak_tracker's taxonomy for report consistency.
enum LeakKind { notDisposed, notGced, gcedLate, growth }

enum LeakSeverity { info, warning, critical }

/// Runtime status of the detector. Defined here (not in the facade) so models
/// can reference it without a dependency cycle.
enum LeakRadarStatus { disabled, preciseOnly, active, serviceUnavailable }
