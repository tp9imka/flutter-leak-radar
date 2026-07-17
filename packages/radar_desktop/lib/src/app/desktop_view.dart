/// Navigation destinations in the Radar Desktop rail. Distinct from
/// `radar_workbench`'s `RadarView` because the desktop adds Dumps/Compare/
/// Trends (offline workspace features) and reuses only the shared VIEWS.
enum DesktopView {
  dumps,
  histogram,
  paths,
  clusters,
  compare,
  trends,
  traces,
  frames,
  errors,
  stalls,
  androidSession,
  androidNative,
  androidCompare,
  androidFfi,
  androidCapture,
  tools;

  bool get isMemory =>
      this == dumps ||
      this == histogram ||
      this == paths ||
      this == clusters ||
      this == compare ||
      this == trends;
  bool get isPerf => this == traces || this == frames;
  bool get isStability => this == errors || this == stalls;
  bool get isAndroid =>
      this == androidSession ||
      this == androidNative ||
      this == androidCompare ||
      this == androidFfi ||
      this == androidCapture;

  /// The SETUP destination — external tool discovery/install/locate.
  /// Its own group: not memory/perf/stability/android, and (unlike
  /// perf/stability) never gated behind a live connection.
  bool get isTools => this == tools;

  String get label => switch (this) {
    DesktopView.dumps => 'Dumps',
    DesktopView.histogram => 'Class histogram',
    DesktopView.paths => 'Retaining paths',
    DesktopView.clusters => 'Leak clusters',
    DesktopView.compare => 'Compare',
    DesktopView.trends => 'Trends',
    DesktopView.traces => 'Traces',
    DesktopView.frames => 'Frames',
    DesktopView.errors => 'Errors',
    DesktopView.stalls => 'Stalls',
    DesktopView.androidSession => 'Session',
    DesktopView.androidNative => 'Native still-live',
    DesktopView.androidCompare => 'Compare',
    DesktopView.androidFfi => 'ffi allocations',
    DesktopView.androidCapture => 'Capture / import',
    DesktopView.tools => 'Tools',
  };
}
