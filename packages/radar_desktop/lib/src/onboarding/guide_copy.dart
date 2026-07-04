/// The visual treatment for a spotlight step's optional note, per the
/// design spec (§3): `accent` for a positive/informational callout
/// (step 1), `warning` for a locked-feature or missing-tool callout
/// (steps 3 and 5).
enum NoteTone { accent, warning }

/// Copy for one spotlight step: kicker, title, body, and an optional
/// note whose [noteTone] selects its rendering (steps 1, 3, and 5 per
/// the design spec).
class GuideSpotlightCopy {
  const GuideSpotlightCopy({
    required this.kicker,
    required this.title,
    required this.body,
    this.note,
    this.noteTone = NoteTone.warning,
  });

  final String kicker;
  final String title;
  final String body;
  final String? note;

  /// Ignored when [note] is null.
  final NoteTone noteTone;
}

/// Spotlight copy verbatim from `docs/flutter_radar_first_run_guide` §3,
/// keyed by controller step (1..5).
const Map<int, GuideSpotlightCopy> guideSpotlightCopy = {
  1: GuideSpotlightCopy(
    kicker: 'CONNECTED MODE',
    title: 'Connect to a running app.',
    body:
        'Paste a Dart VM Service ws:// URI to attach to a live app — or '
        'tap Scan device (Android) to read adb logcat, forward the '
        'port, and fill this in for you.',
    note:
        'Connecting unlocks Performance & Stability, live heap '
        'capture, and Force GC.',
    noteTone: NoteTone.accent,
  ),
  2: GuideSpotlightCopy(
    kicker: 'MEMORY · OFFLINE',
    title: 'Analyze memory with no running app.',
    body:
        'The default surface. Import a heap dump or Perfetto .pftrace '
        '— button or drag-and-drop anywhere. Then browse Dumps, the '
        'Class histogram, Retaining paths, Compare two dumps, and '
        'Trends across a soak.',
  ),
  3: GuideSpotlightCopy(
    kicker: 'PERFORMANCE · STABILITY',
    title: 'Locked until you connect.',
    body:
        'Traces & Frames, Errors & Stalls come alive once you attach '
        "to a running app. If the target doesn't embed the perf "
        "runtime, these views say 'not detected' rather than faking "
        'data.',
    note: 'Locked now (offline) — connect via the bar above to unlock.',
  ),
  4: GuideSpotlightCopy(
    kicker: 'ANDROID NATIVE',
    title: 'Profile below the Dart heap.',
    body:
        'Capture native-heap allocations via adb + heapprofd. See '
        'per-module still-live memory (which .so holds it), '
        'checkpoint Compare, an FFI-allocations lane, and native '
        'symbolization to turn module-only frames into function '
        'names.',
  ),
  5: GuideSpotlightCopy(
    kicker: 'SETUP · TOOLS',
    title: 'External tools & the health dot.',
    body:
        'Tools manages the CLIs Radar shells out to — trace_processor, '
        'adb, llvm-symbolizer. Each shows Found (path + version) or '
        'Missing, with Install, Locate…, and Re-check.',
    note:
        'The health dot in the title bar turns amber when a tool is '
        'missing — tap it to jump here.',
  ),
};
