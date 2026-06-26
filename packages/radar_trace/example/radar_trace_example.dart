// ignore_for_file: avoid_print
import 'dart:async';

import 'package:radar_trace/radar_trace.dart';

Future<void> main() async {
  final tracer = Tracer();

  // --- Synchronous span --------------------------------------------------
  final length = tracer.trace('parse_words', () {
    return 'hello world dart'.split(' ').length;
  });
  print('Word count: $length');

  // --- Async span --------------------------------------------------------
  final result = await tracer.traceAsync('simulate_fetch', () async {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return 'response_payload';
  });
  print('Fetched: $result');

  // --- Nested spans (Zone propagation) -----------------------------------
  tracer.trace('outer', () {
    tracer.trace('inner', () {
      // inner span automatically becomes a child of outer via Zone values.
    });
  });

  // --- Manual start → SpanHandle → stop/fail ----------------------------
  final handle = tracer.start('manual_op', category: 'demo');
  try {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    handle.stop(); // records SpanStatus.ok
  } catch (_) {
    handle.fail(); // records SpanStatus.error
  }

  // --- Latency histogram direct usage ------------------------------------
  final histogram = LatencyHistogram();
  for (final micros in [120, 450, 1800, 12000, 45000]) {
    histogram.record(micros);
  }
  print('p50: ${histogram.percentile(0.5)} µs');
  print('p99: ${histogram.percentile(0.99)} µs');
  print('mean: ${histogram.mean?.toStringAsFixed(1)} µs');

  // --- Read aggregated snapshot ------------------------------------------
  final snap = tracer.snapshot();
  print('\n--- Span summary ---');
  for (final entry in snap.stats.entries) {
    final key = entry.key;
    final h = entry.value.histogram;
    print(
      '${key.name}'
      '${key.category != null ? " [${key.category}]" : ""}: '
      'count=${h.count} '
      'p50=${h.percentile(0.5)} µs '
      'p99=${h.percentile(0.99)} µs',
    );
  }

  if (snap.totalDropCount > 0) {
    print('Dropped (maxKeys): ${snap.totalDropCount}');
  }
}
