// test/engine/vm_status_probe_test.dart
import 'dart:io';

import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/engine/vm_heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/vm_service_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

import '../support/fake_heap_probe.dart';

class _FakeService extends Fake implements VmService {
  @override
  Future<AllocationProfile> getAllocationProfile(
    String isolateId, {
    bool? gc,
    bool? reset,
  }) async {
    return AllocationProfile()..members = [];
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('VmHeapProbe.vmStatus', () {
    test('starts as VmDisabled before any connect attempt', () {
      final probe = VmHeapProbe();
      expect(probe.vmStatus, isA<VmDisabled>());
    });

    test('SocketException on connect → VmSocketError', () async {
      final probe = VmHeapProbe();
      probe.debugInjectConnectionFactory(
        () async => throw const SocketException('refused'),
      );
      await probe.capture(forceGc: false);
      expect(probe.vmStatus, isA<VmSocketError>());
      expect((probe.vmStatus as VmSocketError).message, contains('refused'));
    });

    test('successful connect via inject → VmConnected', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _FakeService(),
        isolateId: 'isolates/test',
      );
      expect(probe.vmStatus, isA<VmConnected>());
    });

    test('dispose → VmDisabled', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _FakeService(),
        isolateId: 'isolates/test',
      );
      expect(probe.vmStatus, isA<VmConnected>());
      await probe.dispose();
      expect(probe.vmStatus, isA<VmDisabled>());
    });

    test('engine exposes vmServiceStatus from probe', () async {
      final probe = VmHeapProbe();
      probe.debugInjectServiceAndCache(
        _FakeService(),
        isolateId: 'isolates/test',
      );
      final engine = LeakEngine(
        probe: probe,
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      );
      await engine.start();
      expect(engine.vmServiceStatus, isA<VmConnected>());
      await engine.stop();
    });

    test('non-VM probe → vmServiceStatus is null on engine', () async {
      final engine = LeakEngine(
        probe: FakeHeapProbe([]),
        analyzer: LeakAnalyzer(SuspectSet.empty()),
      );
      await engine.start();
      expect(engine.vmServiceStatus, isNull);
      await engine.stop();
    });
  });
}
