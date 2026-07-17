import 'dart:io';

import 'package:radar_native/radar_native.dart';
import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

import 'overnight_test_support.dart';

void main() {
  late Directory tempDir;
  late String dir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_store_test_');
    dir = tempDir.path;
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  SessionMeta meta() => SessionMeta(
    package: 'com.example.app',
    device: 'default',
    started: DateTime.utc(2026, 7, 17, 3),
    intervalMicros: 5000000,
    durationMicros: 28800000000,
    flushEveryMicros: 60000000,
  );

  group('SessionMeta', () {
    test('carries schemaVersion and elides live end fields', () {
      final json = meta().toJson();
      expect(json['schemaVersion'], SessionMeta.schemaVersion);
      expect(json['package'], 'com.example.app');
      expect(json.containsKey('finishedAt'), isFalse);
      expect(json.containsKey('endReason'), isFalse);
    });

    test('ended() stamps finishedAt and endReason', () {
      final ended = meta().ended(DateTime.utc(2026, 7, 17, 11), 'interrupted');
      final json = ended.toJson();
      expect(json['endReason'], 'interrupted');
      expect(json['finishedAt'], '2026-07-17T11:00:00.000Z');
    });
  });

  group('SessionStore atomic writes', () {
    test('writeMeta and flushTimeline round-trip through disk', () async {
      final store = SessionStore(dir: dir, lock: FakeSessionLock());
      await store.writeMeta(meta());
      await store.flushTimeline(timelineWithSamples([100, 200]));

      expect(readMeta(dir)['package'], 'com.example.app');
      expect(sampleCount(readTimeline(dir), TriageColumn.nativePssKb), 2);
    });

    test('a write never leaves a stray temp file behind', () async {
      final store = SessionStore(dir: dir, lock: FakeSessionLock());
      await store.flushTimeline(timelineWithSamples([1]));
      final leftovers = Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
    });
  });

  group('SessionStore.appendMark', () {
    test('appends a mark to an existing timeline', () async {
      final store = SessionStore(dir: dir, lock: FakeSessionLock());
      await store.flushTimeline(timelineWithSamples([100, 200]));

      await store.appendMark('reconnect', nowMicros: 12345);

      final timeline = readTimeline(dir);
      expect(sampleCount(timeline, TriageColumn.nativePssKb), 2);
      expect(timeline.marks.single.label, 'reconnect');
      expect(timeline.marks.single.tMicros, 12345);
    });

    test('creates a timeline when none exists yet', () async {
      final store = SessionStore(dir: dir, lock: FakeSessionLock());
      await store.appendMark('start', nowMicros: 1);
      expect(readTimeline(dir).marks.single.label, 'start');
    });

    test(
      'preserves snapshots a flush wrote while the mark waited for the lock',
      () async {
        final lock = FakeSessionLock();
        final store = SessionStore(dir: dir, lock: lock);
        // Two snapshots on disk before the mark begins.
        await store.flushTimeline(timelineWithSamples([100, 200]));

        // Arm the interleave: just before appendMark reads under the lock, a
        // concurrent flush lands a THIRD snapshot. A naive read-then-write mark
        // would clobber it; reading inside the lock must carry it forward.
        lock.beforeNextBody = () async {
          await SessionStore(
            dir: dir,
            lock: FakeSessionLock(),
          ).flushTimeline(timelineWithSamples([100, 200, 300]));
        };

        await store.appendMark('reconnect', nowMicros: 999);

        final timeline = readTimeline(dir);
        expect(
          sampleCount(timeline, TriageColumn.nativePssKb),
          3,
          reason: 'the concurrent flush\'s third snapshot must survive',
        );
        expect(timeline.marks.single.label, 'reconnect');
      },
    );

    test(
      'rejects a corrupt timeline.json rather than papering over it',
      () async {
        File('$dir/timeline.json').writeAsStringSync('{ not json');
        final store = SessionStore(dir: dir, lock: FakeSessionLock());
        await expectLater(
          store.appendMark('x', nowMicros: 1),
          throwsA(anyOf(isA<FormatException>(), isA<Exception>())),
        );
      },
    );
  });

  group('FileSessionLock', () {
    // Cross-PROCESS serialisation (the real scenario: a radar_sample flush vs a
    // radar_mark append in separate processes) rests on the OS advisory lock and
    // cannot be exercised in a single isolate — POSIX fcntl locks do not conflict
    // within one process. The interleave-safety mechanism (read-modify-write
    // inside the lock) is proven above with FakeSessionLock. Here we only assert
    // the real lock acquires, runs the body, and releases.
    test('acquires, runs the body, releases, and is reusable', () async {
      final lock = FileSessionLock('$dir/.session.lock');
      final first = await lock.guard(() async => 'one');
      final second = await lock.guard(() async => 'two');
      expect(first, 'one');
      expect(second, 'two');
      expect(File('$dir/.session.lock').existsSync(), isTrue);
    });
  });
}
