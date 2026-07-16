import 'package:radar_ci/radar_ci.dart';
import 'package:radar_trace/radar_trace.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

import '../support/fake_vm_service.dart';

/// Two isolates, each reporting fixed memory usage; process RSS fixed.
class _MemFakeService extends FakeVmService {
  _MemFakeService({required this.usageById, required this.rss});

  final Map<String, MemoryUsage> usageById;
  final int rss;

  @override
  Future<VM> getVM() async =>
      VM(isolates: [for (final id in usageById.keys) IsolateRef(id: id)]);

  @override
  Future<MemoryUsage> getMemoryUsage(String isolateId) async =>
      usageById[isolateId]!;

  @override
  Future<ProcessMemoryUsage> getProcessMemoryUsage() async =>
      ProcessMemoryUsage(
        root: ProcessMemoryItem(name: 'Total', size: rss),
      );
}

/// Throws from getVM, modelling a dropped VM-service connection mid-run.
class _DeadFakeService extends FakeVmService {
  @override
  Future<VM> getVM() => Future.error(StateError('socket closed'));

  @override
  Future<ProcessMemoryUsage> getProcessMemoryUsage() =>
      Future.error(StateError('socket closed'));
}

MemoryUsage _usage(int used, int cap, int ext) =>
    MemoryUsage(heapUsage: used, heapCapacity: cap, externalUsage: ext);

void main() {
  group('MemorySampler.read', () {
    test(
      'sums heap and external across isolates and reads process RSS',
      () async {
        final sampler = MemorySampler(
          _MemFakeService(
            usageById: {
              'isolates/1': _usage(1000, 2000, 50),
              'isolates/2': _usage(3000, 5000, 70),
            },
            rss: 42000,
          ),
        );

        final reading = await sampler.read(9000);

        expect(reading.tMicros, 9000);
        expect(reading.heapUsed, 4000);
        expect(reading.heapCapacity, 7000);
        expect(reading.external, 120);
        expect(reading.rss, 42000);
        expect(reading.memoryReason, isNull);
        expect(reading.rssReason, isNull);
      },
    );

    test('degrades each metric to null with a reason on RPC failure', () async {
      final sampler = MemorySampler(_DeadFakeService());

      final reading = await sampler.read(5000);

      expect(reading.heapUsed, isNull);
      expect(reading.heapCapacity, isNull);
      expect(reading.external, isNull);
      expect(reading.rss, isNull);
      expect(reading.memoryReason, contains('socket closed'));
      expect(reading.rssReason, contains('socket closed'));
    });
  });

  group('readingsToSeries', () {
    test('emits four named byte series in the documented order', () {
      final series = readingsToSeries([
        const MemoryReading(
          tMicros: 0,
          heapUsed: 10,
          heapCapacity: 20,
          external: 5,
          rss: 100,
        ),
      ]);
      expect(series.map((s) => s.name).toList(), [
        'dart.heap.used',
        'dart.heap.capacity',
        'dart.external',
        'process.rss',
      ]);
      expect(series.every((s) => s.unit == 'bytes'), isTrue);
    });

    test(
      'a failed tick becomes a SeriesGap that brackets the missing region',
      () {
        final series = readingsToSeries([
          const MemoryReading(
            tMicros: 0,
            heapUsed: 10,
            heapCapacity: 20,
            external: 5,
            rss: 100,
          ),
          const MemoryReading(
            tMicros: 5000,
            heapUsed: null,
            heapCapacity: null,
            external: null,
            rss: null,
            memoryReason: 'memory RPC failed: boom',
            rssReason: 'process RPC failed: boom',
          ),
          const MemoryReading(
            tMicros: 10000,
            heapUsed: 30,
            heapCapacity: 40,
            external: 7,
            rss: 300,
          ),
        ]);

        final heapUsed = series.firstWhere((s) => s.name == 'dart.heap.used');
        expect(heapUsed.samples.map((s) => s.tMicros).toList(), [0, 10000]);
        expect(heapUsed.gaps, hasLength(1));
        final MetricSeries s = heapUsed;
        expect(s.gaps.single.startMicros, 0);
        expect(s.gaps.single.endMicros, 10000);
        expect(s.gaps.single.reason, contains('memory RPC failed'));

        final rss = series.firstWhere((s) => s.name == 'process.rss');
        expect(rss.gaps.single.reason, contains('process RPC failed'));
      },
    );

    test('trailing failed ticks still close the gap at the last tick', () {
      final series = readingsToSeries([
        const MemoryReading(
          tMicros: 0,
          heapUsed: 10,
          heapCapacity: 20,
          external: 5,
          rss: 100,
        ),
        const MemoryReading(
          tMicros: 5000,
          heapUsed: null,
          heapCapacity: null,
          external: null,
          rss: null,
          memoryReason: 'gone',
          rssReason: 'gone',
        ),
      ]);
      final heapUsed = series.firstWhere((s) => s.name == 'dart.heap.used');
      expect(heapUsed.samples.single.tMicros, 0);
      expect(heapUsed.gaps.single.startMicros, 0);
      expect(heapUsed.gaps.single.endMicros, 5000);
    });
  });
}
