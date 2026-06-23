// test/precise/leak_object_registry_test.dart
import 'package:flutter_leak_radar/src/model/leak_kind.dart';
import 'package:flutter_leak_radar/src/precise/gc_support.dart';
import 'package:flutter_leak_radar/src/precise/leak_object_registry.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGc implements GcCounter {
  int value = 0;
  @override
  int get currentGcCount => value;
}

void main() {
  test('disposed object still alive after N GC cycles -> notGced', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(gcCounter: gc, disposalGrace: Duration.zero);
    final obj = Object();
    reg.track(obj, tag: 'Thing');
    reg.markDisposed(obj);
    gc.value += 3;
    final leaks = reg.collectLeaks(gcCycles: 3, now: DateTime(2026).add(const Duration(seconds: 10)));
    expect(leaks.single.kind, LeakKind.notGced);
    expect(leaks.single.tag, 'Thing');
    expect(leaks.single.severity, LeakSeverity.critical);
  });

  test('disposed but not enough GC cycles -> no leak yet', () {
    final gc = FakeGc();
    final reg = LeakObjectRegistry(gcCounter: gc, disposalGrace: Duration.zero);
    final obj = Object();
    reg.track(obj, tag: 'Thing');
    reg.markDisposed(obj);
    gc.value += 1;
    expect(reg.collectLeaks(gcCycles: 3, now: DateTime(2026)), isEmpty);
  });

  test('markDisposed on an untracked object is a silent no-op', () {
    final reg = LeakObjectRegistry(gcCounter: FakeGc());
    reg.markDisposed(Object()); // must not throw
    expect(reg.trackedCount, 0);
  });

  test('clear empties the registry', () {
    final reg = LeakObjectRegistry(gcCounter: FakeGc());
    reg.track(Object(), tag: 'A');
    expect(reg.trackedCount, 1);
    reg.clear();
    expect(reg.trackedCount, 0);
  });
}
