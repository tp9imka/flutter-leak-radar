/// Navigation destinations in the Radar Desktop rail. Distinct from
/// `radar_workbench`'s `RadarView` because the desktop adds Dumps/Compare/
/// Trends (offline workspace features) and reuses only the shared VIEWS.
enum DesktopView {
  dumps,
  histogram,
  paths,
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
  androidCapture;

  bool get isMemory =>
      this == dumps ||
      this == histogram ||
      this == paths ||
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

  String get label => switch (this) {
    DesktopView.dumps => 'Dumps',
    DesktopView.histogram => 'Class histogram',
    DesktopView.paths => 'Retaining paths',
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
  };
}
