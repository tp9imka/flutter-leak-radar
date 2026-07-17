/// Headless CI front door for flutter-leak-radar.
///
/// Attaches to (or spawns) a running Dart/Flutter app, samples its memory
/// into gap-aware [MetricSeries], captures allocation profiles and optional
/// heap snapshots at evenly spaced checkpoints, and emits a portable
/// `run.json` ([RadarRunDocument]) for downstream assessment.
///
/// `dart:io`-free surface: everything here is safe to import from a test or
/// analysis context. The process-spawning orchestration lives behind
/// `bin/radar_ci.dart`.
library;

export 'src/gate/verdict_gate.dart';
export 'src/model/run_document.dart';
export 'src/run/attach.dart';
export 'src/run/checkpoint.dart';
export 'src/run/run_clock.dart';
export 'src/run/run_command.dart';
export 'src/run/sampler.dart';
