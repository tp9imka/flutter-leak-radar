/// Root-node classification for a retaining path.
enum RootKind {
  liveTree,
  timer,
  stream,
  staticOrGlobal,
  closure,
  finalizer,
  other;

  /// True when this root is a common source of accidental retention.
  bool get isLeakProne => switch (this) {
    timer || stream || staticOrGlobal || closure || finalizer => true,
    liveTree || other => false,
  };

  String get label => switch (this) {
    liveTree => 'LiveTree',
    timer => 'Timer',
    stream => 'Stream',
    staticOrGlobal => 'Static/Global',
    closure => 'Closure',
    finalizer => 'Finalizer',
    other => 'Other',
  };
}

/// Confidence level of a detected leak cluster.
enum LeakConfidence { heuristic, confirmed }
