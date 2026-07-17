import 'dart:convert';
import 'dart:io';

import 'package:radar_native/radar_native.dart';

/// Immutable header for one sampling session, written to `meta.json`.
///
/// Carries a [schemaVersion] like every other on-disk artifact so a future
/// reader can refuse an unknown shape rather than mis-parse it. [finishedAt]
/// and [endReason] are null while the session is live and filled in by the
/// final flush — so a hard-killed session (no final flush) is distinguishable
/// on disk from one that ended cleanly or was interrupted.
final class SessionMeta {
  /// The JSON schema version written by [toJson].
  static const int schemaVersion = 1;

  /// Sampled package name.
  final String package;

  /// Target device serial, or `'default'` for the sole connected device.
  final String device;

  /// When sampling began (UTC).
  final DateTime started;

  /// Configured inter-sample interval, in microseconds.
  final int intervalMicros;

  /// Configured total session duration, in microseconds.
  final int durationMicros;

  /// Configured flush cadence, in microseconds.
  final int flushEveryMicros;

  /// When sampling ended (UTC), or null while the session is live / was
  /// hard-killed before a final flush.
  final DateTime? finishedAt;

  /// How the session ended: `'completed'`, `'interrupted'`, or `'error'`;
  /// null while live.
  final String? endReason;

  /// Creates a session header.
  const SessionMeta({
    required this.package,
    required this.device,
    required this.started,
    required this.intervalMicros,
    required this.durationMicros,
    required this.flushEveryMicros,
    this.finishedAt,
    this.endReason,
  });

  /// Returns a copy stamped with an end time and [reason].
  SessionMeta ended(DateTime at, String reason) => SessionMeta(
    package: package,
    device: device,
    started: started,
    intervalMicros: intervalMicros,
    durationMicros: durationMicros,
    flushEveryMicros: flushEveryMicros,
    finishedAt: at,
    endReason: reason,
  );

  /// Serialises to a JSON-encodable map carrying `'schemaVersion': 1`.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'package': package,
    'device': device,
    'started': started.toUtc().toIso8601String(),
    'intervalMicros': intervalMicros,
    'durationMicros': durationMicros,
    'flushEveryMicros': flushEveryMicros,
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    if (endReason != null) 'endReason': endReason,
  };
}

/// Serialises a critical section around a session directory so a periodic
/// timeline flush (from `radar_sample`) and a mark append (from a concurrent
/// `radar_mark` process) never interleave their read-modify-writes.
///
/// The seam exists so tests can drive the interleaving deterministically; the
/// production implementation is [FileSessionLock].
abstract interface class SessionLock {
  /// Runs [body] with the session lock held, releasing it afterwards.
  Future<T> guard<T>(Future<T> Function() body);
}

/// [SessionLock] backed by an OS advisory lock on a lock file.
///
/// Uses the non-blocking [FileLock.exclusive] and a bounded retry-with-backoff
/// loop — the "retry-on-conflict loop" — so a mark waits out an in-flight flush
/// (and vice versa) rather than corrupting a half-updated `timeline.json`.
final class FileSessionLock implements SessionLock {
  /// Locks via [lockPath]; retries acquisition up to [maxAttempts] times,
  /// waiting [retryDelay] between attempts.
  const FileSessionLock(
    this.lockPath, {
    this.maxAttempts = 50,
    this.retryDelay = const Duration(milliseconds: 100),
  });

  /// Path to the advisory lock file (created if absent).
  final String lockPath;

  /// Maximum lock-acquisition attempts before giving up.
  final int maxAttempts;

  /// Wait between failed acquisition attempts.
  final Duration retryDelay;

  @override
  Future<T> guard<T>(Future<T> Function() body) async {
    final file = File(lockPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final handle = await file.open(mode: FileMode.write);
    try {
      await _acquire(handle);
      try {
        return await body();
      } finally {
        await handle.unlock();
      }
    } finally {
      await handle.close();
    }
  }

  Future<void> _acquire(RandomAccessFile handle) async {
    var attempt = 0;
    while (true) {
      try {
        await handle.lock(FileLock.exclusive);
        return;
      } on FileSystemException {
        attempt++;
        if (attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}

/// Reads and writes a session directory's `timeline.json` and `meta.json`.
///
/// Every write is atomic (write-to-temp then rename), so a crash — or a hard
/// kill mid-flush — never leaves a half-written, unparseable artifact: the old
/// complete file survives until the rename swaps in the new complete one. All
/// read-modify-write operations run under [lock] so a flush and a concurrent
/// mark append serialise instead of clobbering each other.
final class SessionStore {
  /// Creates a store over session directory [dir], serialised by [lock].
  SessionStore({required this.dir, required this.lock});

  /// The session directory holding `timeline.json` and `meta.json`.
  final String dir;

  /// Lock serialising concurrent read-modify-writes on the session.
  final SessionLock lock;

  static const JsonEncoder _encoder = JsonEncoder.withIndent('  ');
  int _tempSeq = 0;

  /// Path to the timeline artifact.
  File get timelineFile => File('$dir/timeline.json');

  /// Path to the metadata artifact.
  File get metaFile => File('$dir/meta.json');

  /// Atomically (re)writes `meta.json` from [meta].
  Future<void> writeMeta(SessionMeta meta) =>
      lock.guard(() => _atomicWrite(metaFile, _encoder.convert(meta.toJson())));

  /// Atomically (re)writes `timeline.json` from [timeline].
  Future<void> flushTimeline(TriageTimeline timeline) => lock.guard(
    () => _atomicWrite(timelineFile, _encoder.convert(timeline.toJson())),
  );

  /// Appends a [TriageMark] labelled [label] at [nowMicros], preserving any
  /// snapshots a concurrent flush wrote.
  ///
  /// The read of the current timeline happens **inside** the lock, so if a
  /// flush landed while this call waited for the lock, the fresh snapshots are
  /// read and carried forward rather than overwritten with a stale copy.
  /// Throws [FormatException] via [TriageTimeline.fromJson] if the existing
  /// `timeline.json` is corrupt — a mark must never paper over a bad file.
  Future<void> appendMark(String label, {required int nowMicros}) =>
      lock.guard(() async {
        final current = await _readTimeline();
        final updated = TriageTimeline(
          columns: current.columns,
          marks: [
            ...current.marks,
            TriageMark(tMicros: nowMicros, label: label),
          ],
        );
        await _atomicWrite(timelineFile, _encoder.convert(updated.toJson()));
      });

  Future<TriageTimeline> _readTimeline() async {
    if (!await timelineFile.exists()) return const TriageTimeline();
    final raw = await timelineFile.readAsString();
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    return TriageTimeline.fromJson(decoded);
  }

  Future<void> _atomicWrite(File target, String contents) async {
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    final temp = File('${target.path}.$pid.${_tempSeq++}.tmp');
    await temp.writeAsString('$contents\n');
    await temp.rename(target.path);
  }
}
