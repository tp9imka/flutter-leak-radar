// lib/src/precise/leak_object_registry.dart
import '../model/leak_finding.dart';
import '../model/leak_kind.dart';
import 'gc_support.dart';

class _Entry {
  _Entry(Object obj, this.tag) : ref = WeakReference<Object>(obj);

  /// WeakReference only — never store a strong ref that extends the lifetime.
  final WeakReference<Object> ref;
  final String tag;
  int? disposedGc;
  DateTime? disposedAt;
}

/// Precise leak detection via [WeakReference] and a GC-cycle counter.
///
/// Call [track] when an object is created and [markDisposed] when it is
/// disposed. [collectLeaks] inspects surviving objects that were disposed at
/// least [gcCycles] GC cycles ago and past [disposalGrace], emitting a
/// [LeakKind.notGced] finding for each one.
class LeakObjectRegistry {
  LeakObjectRegistry({
    GcCounter? gcCounter,
    this.disposalGrace = const Duration(seconds: 2),
  }) : _gc = gcCounter ?? const DeveloperGcCounter();

  final GcCounter _gc;

  /// Minimum wall-clock time after disposal before an object is considered
  /// a leak, regardless of GC cycles elapsed.
  final Duration disposalGrace;

  final Map<int, _Entry> _entries = <int, _Entry>{};

  /// Number of objects currently tracked (including disposed-but-not-yet-collected).
  int get trackedCount => _entries.length;

  /// Begin tracking [obj] under the given [tag] label.
  void track(Object obj, {required String tag}) {
    _entries[identityHashCode(obj)] = _Entry(obj, tag);
  }

  /// Record that [obj] has been disposed.
  ///
  /// Silently ignores objects that were never passed to [track].
  void markDisposed(Object obj) {
    final entry = _entries[identityHashCode(obj)];
    if (entry == null) return;
    entry.disposedGc = _gc.currentGcCount;
    entry.disposedAt = DateTime.now();
  }

  /// Returns all objects that are disposed, survived >= [gcCycles] GC cycles,
  /// are past [disposalGrace], and are still alive (WeakReference non-null).
  ///
  /// Entries whose target has been collected are pruned from the registry.
  List<LeakFinding> collectLeaks({int gcCycles = 3, DateTime? now}) {
    final at = now ?? DateTime.now();
    final current = _gc.currentGcCount;
    final leaks = <LeakFinding>[];
    final dead = <int>[];

    _entries.forEach((key, entry) {
      final target = entry.ref.target;
      if (target == null) {
        dead.add(key);
        return;
      }
      final disposedGc = entry.disposedGc;
      final disposedAt = entry.disposedAt;
      if (disposedGc == null || disposedAt == null) return;
      final survivedCycles = current - disposedGc >= gcCycles;
      // Duration.zero means "no grace required" — always satisfied.
      // For positive grace, at must be after disposedAt by at least that amount.
      final pastGrace = disposalGrace == Duration.zero ||
          at.difference(disposedAt) >= disposalGrace;
      if (survivedCycles && pastGrace) {
        leaks.add(LeakFinding(
          className: target.runtimeType.toString(),
          kind: LeakKind.notGced,
          severity: LeakSeverity.critical,
          liveCount: 1,
          growth: 0,
          tag: entry.tag,
        ));
      }
    });

    for (final k in dead) {
      _entries.remove(k);
    }
    return leaks;
  }

  /// Removes all tracked entries.
  void clear() => _entries.clear();
}
