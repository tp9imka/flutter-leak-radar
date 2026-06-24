/// Category of a detected leak finding.
///
/// Mirrors package:leak_tracker's taxonomy for report consistency.
enum LeakKind {
  /// Object was not disposed before being GCed.
  notDisposed,

  /// Object was expected to be GCed after disposal but was not.
  notGced,

  /// Object was GCed later than expected after disposal.
  gcedLate,

  /// Per-class instance count grew across heap snapshots.
  growth,

  /// Object is reachable from a non-live GC root — confirmed live leak
  /// detected via retaining-path graph analysis.
  retainedByNonLiveRoot,
}

/// Indicates how severe a [LeakFinding] is.
enum LeakSeverity {
  /// Informational — likely not a leak, worth monitoring.
  info,

  /// Probable leak — instance count growing beyond expected bounds.
  warning,

  /// Definite leak — object confirmed live well past expected lifetime.
  critical,
}

/// Runtime status of the leak detector.
///
/// Defined here (not in the facade) so models can reference it without a
/// dependency cycle.
enum LeakRadarStatus {
  /// Engine is not running (disabled in config or release build).
  disabled,

  /// Only precise object tracking is active; VM service heap probes
  /// are unavailable on this platform/build.
  preciseOnly,

  /// Fully active — both heap-growth and precise tracking are running.
  active,

  /// Engine started but the VM service probe returned an unrecoverable error.
  serviceUnavailable,
}
