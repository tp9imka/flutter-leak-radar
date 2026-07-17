import 'package:meta/meta.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:vm_service/vm_service.dart';

/// One memory reading across all four tracked metrics at [tMicros].
///
/// A null value on any metric means its RPC failed at this tick; the matching
/// `*Reason` explains why. Honest absence — never a fabricated 0 — so the
/// series builder can record a gap instead of bridging.
@immutable
final class MemoryReading {
  /// Host wall-clock microseconds since epoch.
  final int tMicros;

  /// Summed `heapUsage` across isolates, or null on RPC failure.
  final int? heapUsed;

  /// Summed `heapCapacity` across isolates, or null on RPC failure.
  final int? heapCapacity;

  /// Summed `externalUsage` across isolates, or null on RPC failure.
  final int? external;

  /// Process retained size from `getProcessMemoryUsage`, or null on failure.
  final int? rss;

  /// Why the isolate memory metrics are absent this tick, if they are.
  final String? memoryReason;

  /// Why [rss] is absent this tick, if it is.
  final String? rssReason;

  /// Creates a memory reading.
  const MemoryReading({
    required this.tMicros,
    required this.heapUsed,
    required this.heapCapacity,
    required this.external,
    required this.rss,
    this.memoryReason,
    this.rssReason,
  });
}

/// Reads live memory metrics from a target VM over its service connection.
final class MemorySampler {
  /// Wraps an established [VmService] connection.
  const MemorySampler(this._service);

  final VmService _service;

  /// Reads all four metrics at [tMicros].
  ///
  /// The isolate metrics (`heapUsed`/`heapCapacity`/`external`) share one RPC
  /// path and degrade together; [rss] degrades independently. Never throws —
  /// a failure surfaces as null values with a reason.
  Future<MemoryReading> read(int tMicros) async {
    int? heapUsed;
    int? heapCapacity;
    int? external;
    String? memoryReason;
    try {
      final vm = await _service.getVM();
      final isolates = vm.isolates ?? const <IsolateRef>[];
      var used = 0;
      var capacity = 0;
      var ext = 0;
      for (final isolate in isolates) {
        final id = isolate.id;
        if (id == null) continue;
        final usage = await _service.getMemoryUsage(id);
        used += usage.heapUsage ?? 0;
        capacity += usage.heapCapacity ?? 0;
        ext += usage.externalUsage ?? 0;
      }
      heapUsed = used;
      heapCapacity = capacity;
      external = ext;
    } catch (error) {
      memoryReason = 'isolate memory RPC failed: $error';
    }

    int? rss;
    String? rssReason;
    try {
      final process = await _service.getProcessMemoryUsage();
      rss = process.root?.size;
      if (rss == null) rssReason = 'process memory usage unavailable';
    } catch (error) {
      rssReason = 'process memory RPC failed: $error';
    }

    return MemoryReading(
      tMicros: tMicros,
      heapUsed: heapUsed,
      heapCapacity: heapCapacity,
      external: external,
      rss: rss,
      memoryReason: memoryReason,
      rssReason: rssReason,
    );
  }
}

typedef _MetricSelector =
    ({int? value, String? reason}) Function(MemoryReading);

const List<({String name, _MetricSelector select})> _metricDescriptors = [
  (name: 'dart.heap.used', select: _selectHeapUsed),
  (name: 'dart.heap.capacity', select: _selectHeapCapacity),
  (name: 'dart.external', select: _selectExternal),
  (name: 'process.rss', select: _selectRss),
];

({int? value, String? reason}) _selectHeapUsed(MemoryReading r) =>
    (value: r.heapUsed, reason: r.memoryReason);
({int? value, String? reason}) _selectHeapCapacity(MemoryReading r) =>
    (value: r.heapCapacity, reason: r.memoryReason);
({int? value, String? reason}) _selectExternal(MemoryReading r) =>
    (value: r.external, reason: r.memoryReason);
({int? value, String? reason}) _selectRss(MemoryReading r) =>
    (value: r.rss, reason: r.rssReason);

/// Builds the four byte-unit [MetricSeries] from time-ordered [readings],
/// turning runs of failed ticks into gaps that assessment will not bridge.
List<MetricSeries> readingsToSeries(List<MemoryReading> readings) => [
  for (final descriptor in _metricDescriptors)
    _buildSeries(descriptor.name, readings, descriptor.select),
];

MetricSeries _buildSeries(
  String name,
  List<MemoryReading> readings,
  _MetricSelector select,
) {
  final samples = <MetricSample>[];
  final gaps = <SeriesGap>[];

  int? lastGoodMicros;
  final pendingNulls = <int>[];
  String? pendingReason;

  void flushGap(int? endMicros) {
    if (pendingNulls.isEmpty) return;
    final start = lastGoodMicros ?? pendingNulls.first;
    final end = endMicros ?? pendingNulls.last;
    gaps.add(
      SeriesGap(
        startMicros: start,
        endMicros: end,
        reason: pendingReason ?? 'not measured',
      ),
    );
    pendingNulls.clear();
    pendingReason = null;
  }

  for (final reading in readings) {
    final picked = select(reading);
    if (picked.value == null) {
      pendingNulls.add(reading.tMicros);
      pendingReason ??= picked.reason;
      continue;
    }
    flushGap(reading.tMicros);
    samples.add(
      MetricSample(tMicros: reading.tMicros, value: picked.value!.toDouble()),
    );
    lastGoodMicros = reading.tMicros;
  }
  flushGap(null);

  return MetricSeries(name: name, unit: 'bytes', samples: samples, gaps: gaps);
}
