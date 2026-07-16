// test/engine/project_package_chain_test.dart
//
// Drives the engine's project-package detection chain:
//   explicit (config) → probe rootLib package → AppPackageSet.autoDetect → none
import 'package:flutter_leak_radar/flutter_leak_radar.dart' show ClassOrigin;
import 'package:flutter_leak_radar/src/analysis/leak_analyzer.dart';
import 'package:flutter_leak_radar/src/config/graph_scan.dart';
import 'package:flutter_leak_radar/src/config/leak_radar_config.dart';
import 'package:flutter_leak_radar/src/config/leak_rule.dart';
import 'package:flutter_leak_radar/src/config/suspect_set.dart';
import 'package:flutter_leak_radar/src/engine/class_sample.dart';
import 'package:flutter_leak_radar/src/engine/heap_probe.dart';
import 'package:flutter_leak_radar/src/engine/leak_engine.dart';
import 'package:flutter_leak_radar/src/model/leak_report.dart';
import 'package:flutter_leak_radar/src/model/retaining_path.dart';
import 'package:flutter_test/flutter_test.dart';

/// A HeapProbe that also exposes a scriptable root-library package (the
/// `getIsolate(main).rootLib` RPC surface, faked). [rootPackage] null models a
/// physical device where the RPC is unreachable.
class _ChainFakeProbe implements HeapProbe, RootLibrarySource {
  _ChainFakeProbe(this._snapshots, {this.rootPackage});

  final List<HeapSnapshot> _snapshots;
  String? rootPackage;
  int rootLibraryCalls = 0;
  int _index = 0;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async {
    if (_snapshots.isEmpty) {
      return HeapSnapshot(samples: const [], capturedAt: DateTime.now());
    }
    final snap = _snapshots[_index];
    if (_index < _snapshots.length - 1) _index++;
    return snap;
  }

  @override
  Future<String?> rootLibraryPackage() async {
    rootLibraryCalls++;
    return rootPackage;
  }

  @override
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances = 10,
  }) async => null;

  @override
  Future<void> dispose() async {}
}

HeapSnapshot _snap(int appCount, {String? lib, int t = 1}) => HeapSnapshot(
  capturedAt: DateTime(2026, 1, 1, 0, 0, t),
  samples: [
    ClassSample(
      className: 'AppBloc',
      instancesCurrent: appCount,
      bytesCurrent: appCount * 40,
      library: lib,
      timestamp: DateTime(2026, 1, 1, 0, 0, t),
    ),
  ],
);

LeakEngine _engine(_ChainFakeProbe probe, {GraphScan? graphScan}) => LeakEngine(
  probe: probe,
  analyzer: const LeakAnalyzer(
    SuspectSet(<LeakRule>[LeakRule.growth('*Bloc', appOnly: false)]),
  ),
  config: LeakRadarConfig(graphScan: graphScan),
);

Future<LeakReport> _scanTwice(LeakEngine engine) async {
  await engine.scan();
  return engine.scan();
}

void main() {
  test(
    'explicit config packages win and are never overridden by the RPC',
    () async {
      final probe = _ChainFakeProbe([
        _snap(1, lib: 'package:my_app/a.dart', t: 1),
        _snap(3, lib: 'package:my_app/a.dart', t: 2),
      ], rootPackage: 'root_pkg');
      final engine = _engine(
        probe,
        graphScan: const GraphScan(appPackages: ['my_app']),
      );
      await engine.start();
      final report = await _scanTwice(engine);
      await engine.stop();

      expect(report.projectPackageSource, 'explicit');
      expect(
        probe.rootLibraryCalls,
        0,
        reason: 'explicit short-circuits the RPC',
      );
      expect(
        report.findings.singleWhere((f) => f.className == 'AppBloc').origin,
        ClassOrigin.project,
      );
    },
  );

  test('rootLib package is used and takes precedence over auto-detect', () async {
    // Snapshots are package:my_app, but the RPC reports root_pkg. rootLib wins,
    // so my_app is classified as a dependency (not project).
    final probe = _ChainFakeProbe([
      _snap(1, lib: 'package:my_app/a.dart', t: 1),
      _snap(3, lib: 'package:my_app/a.dart', t: 2),
    ], rootPackage: 'root_pkg');
    final engine = _engine(probe);
    await engine.start();
    final report = await _scanTwice(engine);
    await engine.stop();

    expect(report.projectPackageSource, 'rootLib');
    expect(probe.rootLibraryCalls, greaterThan(0));
    expect(
      report.findings.singleWhere((f) => f.className == 'AppBloc').origin,
      ClassOrigin.dependency,
    );
  });

  test('rootLib failure falls through to AppPackageSet.autoDetect', () async {
    final probe = _ChainFakeProbe([
      _snap(1, lib: 'package:my_app/a.dart', t: 1),
      _snap(3, lib: 'package:my_app/a.dart', t: 2),
    ], rootPackage: null);
    final engine = _engine(probe);
    await engine.start();
    final report = await _scanTwice(engine);
    await engine.stop();

    expect(report.projectPackageSource, 'autoDetected');
    expect(
      report.findings.singleWhere((f) => f.className == 'AppBloc').origin,
      ClassOrigin.project,
    );
  });

  test('no signal anywhere resolves to none', () async {
    // No explicit config, RPC returns null, and snapshots carry no library so
    // auto-detect finds nothing.
    final probe = _ChainFakeProbe([
      _snap(1, t: 1),
      _snap(3, t: 2),
    ], rootPackage: null);
    final engine = _engine(probe);
    await engine.start();
    final report = await _scanTwice(engine);
    await engine.stop();

    expect(report.projectPackageSource, 'none');
    expect(
      report.findings.singleWhere((f) => f.className == 'AppBloc').origin,
      ClassOrigin.unknown,
    );
  });

  test(
    'a probe without the RPC capability still resolves via auto-detect',
    () async {
      // The stock FakeHeapProbe does not implement RootLibrarySource; the chain
      // must skip step 2 without error.
      final probe = _NoRpcProbe([
        _snap(1, lib: 'package:my_app/a.dart', t: 1),
        _snap(3, lib: 'package:my_app/a.dart', t: 2),
      ]);
      final engine = LeakEngine(
        probe: probe,
        analyzer: const LeakAnalyzer(
          SuspectSet(<LeakRule>[LeakRule.growth('*Bloc', appOnly: false)]),
        ),
      );
      await engine.start();
      await engine.scan();
      final report = await engine.scan();
      await engine.stop();

      expect(report.projectPackageSource, 'autoDetected');
    },
  );
}

/// A HeapProbe with no RootLibrarySource capability.
class _NoRpcProbe implements HeapProbe {
  _NoRpcProbe(this._snapshots);

  final List<HeapSnapshot> _snapshots;
  int _index = 0;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<HeapSnapshot> capture({required bool forceGc}) async {
    final snap = _snapshots[_index];
    if (_index < _snapshots.length - 1) _index++;
    return snap;
  }

  @override
  Future<RetainingPathView?> retainingPath(
    String className, {
    int maxInstances = 10,
  }) async => null;

  @override
  Future<void> dispose() async {}
}
