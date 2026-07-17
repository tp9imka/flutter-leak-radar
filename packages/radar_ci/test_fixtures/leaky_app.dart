// Hermetic planted-leak fixture for radar_ci's end-to-end gate test.
//
// Retains one 64 KB chunk in a top-level list every 50 ms and never releases
// it — a deliberately strong, monotonic Dart-heap leak. Run this under
// `dart --enable-vm-service=0` so the VM prints its service URI; the e2e test
// attaches, samples for ~20 s, and asserts the gate certifies growth (exit 3).
//
// Not a `package:test` test — a plain script spawned as a subprocess. It keeps
// itself alive with a periodic timer and self-destructs after [_maxLifetime]
// so a crashed test run can never orphan it.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// Bytes retained per tick (64 KB). Large enough that the growing live set
/// dominates GC sawtooth across the sampling window.
const int _chunkBytes = 64 * 1024;

/// Interval between allocations.
const Duration _tick = Duration(milliseconds: 50);

/// Hard self-destruct, so an interrupted test never leaves this running. Must
/// outlive the e2e's full ~3 min sampling window (plus the test's own timeout)
/// — the test force-kills the fixture itself on a clean finish.
const Duration _maxLifetime = Duration(minutes: 6);

/// The planted leak: every chunk is retained here for the process lifetime.
final List<Uint8List> _leaked = <Uint8List>[];

void main() {
  Timer.periodic(_tick, (_) {
    final chunk = Uint8List(_chunkBytes);
    // Touch one byte per 4 KB page so the memory is genuinely resident.
    for (var offset = 0; offset < chunk.length; offset += 4096) {
      chunk[offset] = 1;
    }
    _leaked.add(chunk);
  });
  Timer(_maxLifetime, () => exit(0));
  stderr.writeln(
    'leaky_app: retaining ${_chunkBytes ~/ 1024} KB every '
    '${_tick.inMilliseconds} ms (planted monotonic leak)',
  );
}
