// Hermetic healthy fixture — the non-growing control for radar_ci's e2e gate.
//
// The tuning problem this solves: the gate fails a monotonic rise in ANY of
// {dart.heap.used, dart.external, process.rss}, and those pull in opposite
// directions for a synthetic Dart process:
//   * A do-nothing isolate keeps RSS flat, but the garbage from handling the
//     sampler's own VM-service RPCs never gets scavenged (nothing triggers a
//     GC), so dart.heap.used micro-creeps upward and reads monotonic.
//   * Sustained fresh allocation triggers frequent GCs that flush that garbage
//     (heap.used goes flat) — but each GC nudges the VM's heap capacity up, and
//     RSS follows and never falls, so RSS reads monotonic instead.
// The stable point (found by calibration — see the e2e report) is a mostly-idle
// isolate that forces just a FEW GCs: light in-place work every tick, plus one
// large transient allocation every ~30 s. Those infrequent flushes keep
// heap.used bounded (plateau) while being too rare to ratchet RSS (plateau).
// dart.external stays ~0 (plateau). The gate passes (exit 0). Run under
// `dart --enable-vm-service=0`; see leaky_app.dart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Interval between work ticks.
const Duration _tick = Duration(milliseconds: 50);

/// Hard self-destruct, so an interrupted test never leaves this running. Must
/// outlive the e2e's full ~3 min sampling window (plus the test's own timeout)
/// — the test force-kills the fixture itself on a clean finish.
const Duration _maxLifetime = Duration(minutes: 6);

/// Force a flushing GC this often (~30 s at [_tick]). Frequent enough to keep
/// dart.heap.used bounded, rare enough not to ratchet process.rss.
const int _flushEveryTicks = 600;

/// Size of the transient buffer whose allocation forces the flushing GC (8 MB).
const int _flushBytes = 8 * 1024 * 1024;

/// A fixed buffer overwritten in place every tick — steady work, no allocation.
final Uint8List _fixed = Uint8List(64 * 1024);

/// Kept live so the flush allocation is never optimized away.
int _sink = 0;

void main() {
  var tick = 0;
  Timer.periodic(_tick, (_) {
    tick++;
    for (var offset = 0; offset < _fixed.length; offset += 4096) {
      _fixed[offset] = (_fixed[offset] + 1) & 0xff;
    }
    if (tick % _flushEveryTicks == 0) {
      // One large transient allocation forces a GC that reclaims the accrued
      // measurement garbage, then is itself dropped.
      final flush = Uint8List(_flushBytes);
      for (var offset = 0; offset < flush.length; offset += 4096) {
        flush[offset] = 1;
      }
      _sink += flush[0];
    }
  });
  Timer(_maxLifetime, () {
    stderr.writeln('healthy_app: exiting (sink=$_sink)');
    exit(0);
  });
  stderr.writeln(
    'healthy_app: steady in-place work with a ${_flushBytes ~/ 1024 ~/ 1024} MB '
    'flush every ${_flushEveryTicks * _tick.inMilliseconds ~/ 1000} s',
  );
}
