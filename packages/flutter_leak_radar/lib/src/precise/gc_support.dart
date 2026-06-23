// lib/src/precise/gc_support.dart
import 'dart:developer' as developer;

/// Abstraction over the VM's GC cycle counter so tests can drive it.
abstract interface class GcCounter {
  int get currentGcCount;
}

/// Real counter backed by `dart:developer`'s reachabilityBarrier.
class DeveloperGcCounter implements GcCounter {
  const DeveloperGcCounter();

  @override
  int get currentGcCount => developer.reachabilityBarrier;
}
