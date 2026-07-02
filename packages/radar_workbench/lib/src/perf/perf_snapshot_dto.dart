import 'dart:developer' as developer;

/// DTO mirroring the `ext.perf_radar.snapshot` JSON contract.
///
/// All fields that the host marks as nullable remain nullable here.
/// Never fabricate a value; leave it null and let the UI render "—".

// ── Traces ────────────────────────────────────────────────────────────────────

/// Statistics for a single traced operation key.
final class TraceKeyDto {
  const TraceKeyDto({
    required this.name,
    this.category,
    required this.count,
    required this.meanMicros,
    required this.maxMicros,
    required this.totalMicros,
    this.p50,
    this.p95,
    this.p99,
    this.avgInterCallIntervalMicros,
    this.callsPerSecond,
    required this.errorCount,
    required this.firstStartMicros,
    required this.lastStartMicros,
  });

  final String name;
  final String? category;
  final int count;
  final int meanMicros;
  final int maxMicros;
  final int totalMicros;
  final int? p50;
  final int? p95;
  final int? p99;
  final int? avgInterCallIntervalMicros;
  final double? callsPerSecond;
  final int errorCount;
  final int firstStartMicros;
  final int lastStartMicros;

  /// Whether this key is HOT: high-frequency with a tight inter-call interval.
  ///
  /// HOT = call rate ≥ 5/s **or** (count ≥ 20 and interval ≤ 200 ms).
  /// Used for the HOT tag and the "hot / dup" filter.
  bool get isHot {
    final rate = callsPerSecond;
    if (rate != null && rate >= 5.0) return true;
    final interval = avgInterCallIntervalMicros;
    return count >= 20 && interval != null && interval <= 200000;
  }

  factory TraceKeyDto.fromJson(Map<String, Object?> j) => TraceKeyDto(
    name: j['name'] as String,
    category: j['category'] as String?,
    count: j['count'] as int,
    meanMicros: j['meanMicros'] as int,
    maxMicros: j['maxMicros'] as int,
    totalMicros: j['totalMicros'] as int,
    p50: j['p50'] as int?,
    p95: j['p95'] as int?,
    p99: j['p99'] as int?,
    avgInterCallIntervalMicros: j['avgInterCallIntervalMicros'] as int?,
    callsPerSecond: (j['callsPerSecond'] as num?)?.toDouble(),
    errorCount: j['errorCount'] as int,
    firstStartMicros: j['firstStartMicros'] as int,
    lastStartMicros: j['lastStartMicros'] as int,
  );
}

/// Top-level traces container.
final class TracesDto {
  const TracesDto({required this.totalDropCount, required this.keys});

  final int totalDropCount;
  final List<TraceKeyDto> keys;

  factory TracesDto.fromJson(Map<String, Object?> j) => TracesDto(
    totalDropCount: j['totalDropCount'] as int,
    keys: (j['keys'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(TraceKeyDto.fromJson)
        .toList(),
  );
}

// ── Frames ────────────────────────────────────────────────────────────────────

/// A single frame timing sample.
final class RecentFrameDto {
  const RecentFrameDto({
    required this.totalMicros,
    required this.buildMicros,
    required this.rasterMicros,
  });

  final int totalMicros;
  final int buildMicros;
  final int rasterMicros;

  /// Whether this frame is jank (total > 16 666 µs = 60 fps budget).
  bool get isJank => totalMicros > 16666;

  factory RecentFrameDto.fromJson(Map<String, Object?> j) => RecentFrameDto(
    totalMicros: j['totalMicros'] as int,
    buildMicros: j['buildMicros'] as int,
    rasterMicros: j['rasterMicros'] as int,
  );
}

/// Frame statistics container.
final class FramesDto {
  const FramesDto({
    required this.frameCount,
    required this.jankCount,
    this.buildP50,
    this.buildP95,
    this.buildP99,
    this.rasterP50,
    this.rasterP95,
    this.rasterP99,
    this.totalP50,
    this.totalP95,
    this.totalP99,
    required this.recentFrames,
  });

  final int frameCount;
  final int jankCount;
  final int? buildP50;
  final int? buildP95;
  final int? buildP99;
  final int? rasterP50;
  final int? rasterP95;
  final int? rasterP99;
  final int? totalP50;
  final int? totalP95;
  final int? totalP99;
  final List<RecentFrameDto> recentFrames;

  double? get jankPercent =>
      frameCount > 0 ? jankCount / frameCount * 100 : null;

  factory FramesDto.fromJson(Map<String, Object?> j) => FramesDto(
    frameCount: j['frameCount'] as int,
    jankCount: j['jankCount'] as int,
    buildP50: j['buildP50'] as int?,
    buildP95: j['buildP95'] as int?,
    buildP99: j['buildP99'] as int?,
    rasterP50: j['rasterP50'] as int?,
    rasterP95: j['rasterP95'] as int?,
    rasterP99: j['rasterP99'] as int?,
    totalP50: j['totalP50'] as int?,
    totalP95: j['totalP95'] as int?,
    totalP99: j['totalP99'] as int?,
    recentFrames: (j['recentFrames'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(RecentFrameDto.fromJson)
        .toList(),
  );
}

// ── Stability ─────────────────────────────────────────────────────────────────

/// A single recorded error event.
final class ErrorRecordDto {
  const ErrorRecordDto({
    required this.message,
    this.context,
    required this.clockMicros,
    this.stackTraceString,
  });

  final String message;
  final String? context;
  final int clockMicros;
  final String? stackTraceString;

  factory ErrorRecordDto.fromJson(Map<String, Object?> j) => ErrorRecordDto(
    message: j['message'] as String,
    context: j['context'] as String?,
    clockMicros: j['clockMicros'] as int,
    stackTraceString: j['stackTraceString'] as String?,
  );
}

/// A single recorded stall event.
final class StallRecordDto {
  const StallRecordDto({
    required this.durationMicros,
    required this.clockMicros,
  });

  final int durationMicros;
  final int clockMicros;

  factory StallRecordDto.fromJson(Map<String, Object?> j) => StallRecordDto(
    durationMicros: j['durationMicros'] as int,
    clockMicros: j['clockMicros'] as int,
  );
}

/// Stability container.
final class StabilityDto {
  const StabilityDto({
    required this.errorCount,
    required this.stallCount,
    required this.recentErrors,
    required this.recentStalls,
  });

  final int errorCount;
  final int stallCount;
  final List<ErrorRecordDto> recentErrors;
  final List<StallRecordDto> recentStalls;

  factory StabilityDto.fromJson(Map<String, Object?> j) => StabilityDto(
    errorCount: j['errorCount'] as int,
    stallCount: j['stallCount'] as int,
    recentErrors: (j['recentErrors'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(ErrorRecordDto.fromJson)
        .toList(),
    recentStalls: (j['recentStalls'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(StallRecordDto.fromJson)
        .toList(),
  );
}

// ── Top-level snapshot ────────────────────────────────────────────────────────

/// The full decoded snapshot from `ext.perf_radar.snapshot`.
final class PerfSnapshotDto {
  const PerfSnapshotDto({
    required this.traces,
    required this.frames,
    required this.stability,
  });

  final TracesDto traces;
  final FramesDto frames;
  final StabilityDto stability;

  /// Parses the root JSON map returned by the VM service extension.
  ///
  /// Returns null and logs on any parse error — callers must handle null.
  static PerfSnapshotDto? tryFromJson(
    Map<String, Object?> json, {
    String logName = 'leakRadarDevTools.perf',
  }) {
    try {
      return PerfSnapshotDto(
        traces: TracesDto.fromJson(json['traces'] as Map<String, Object?>),
        frames: FramesDto.fromJson(json['frames'] as Map<String, Object?>),
        stability: StabilityDto.fromJson(
          json['stability'] as Map<String, Object?>,
        ),
      );
    } catch (e, s) {
      developer.log(
        'PerfSnapshotDto.tryFromJson failed: $e',
        name: logName,
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }
}
