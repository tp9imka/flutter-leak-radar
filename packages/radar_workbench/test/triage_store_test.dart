import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

void main() {
  final t0 = DateTime(2026, 7, 1, 9);
  final t1 = DateTime(2026, 7, 2, 9);

  TriageEntry entry(
    String signature, {
    TriageStatus status = TriageStatus.known,
    DateTime? firstSeen,
    String? note,
  }) => TriageEntry(
    signature: signature,
    firstSeen: firstSeen ?? t0,
    status: status,
    note: note,
  );

  group('TriageStore.displayFor', () {
    test('no entry for a present signature reads NEW (fresh)', () {
      final displays = TriageStore.empty.displayFor(['sigA']);
      expect(displays['sigA'], TriageDisplay.fresh);
    });

    test('a present known entry reads KNOWN', () {
      final store = TriageStore.empty.upsert(entry('sigA'));
      expect(store.displayFor(['sigA'])['sigA'], TriageDisplay.known);
    });

    test('a present acknowledged entry reads ACK', () {
      final store = TriageStore.empty.upsert(
        entry('sigA', status: TriageStatus.acknowledged),
      );
      expect(store.displayFor(['sigA'])['sigA'], TriageDisplay.acknowledged);
    });

    test(
      'a known entry ABSENT from the current set reads GONE — the payoff',
      () {
        final store = TriageStore.empty.upsert(entry('sigA'));
        // sigA is not among the current signatures → it was fixed.
        final displays = store.displayFor(['sigB']);
        expect(displays['sigA'], TriageDisplay.gone);
        expect(displays['sigB'], TriageDisplay.fresh);
      },
    );

    test('GONE wins over a stored ACK status when the signature is absent', () {
      final store = TriageStore.empty.upsert(
        entry('sigA', status: TriageStatus.acknowledged),
      );
      expect(store.displayFor(const [])['sigA'], TriageDisplay.gone);
    });

    test('keys the result by the union of current and stored signatures', () {
      final store = TriageStore.empty
          .upsert(entry('gone'))
          .upsert(entry('known'));
      final displays = store.displayFor(['known', 'brandNew']);
      expect(displays.keys.toSet(), {'known', 'brandNew', 'gone'});
      expect(displays['known'], TriageDisplay.known);
      expect(displays['brandNew'], TriageDisplay.fresh);
      expect(displays['gone'], TriageDisplay.gone);
    });
  });

  group('TriageStore mutation is immutable', () {
    test('upsert returns a new store and leaves the original untouched', () {
      final original = TriageStore.empty;
      final next = original.upsert(entry('sigA'));
      expect(original.entryFor('sigA'), isNull);
      expect(next.entryFor('sigA'), isNotNull);
      expect(identical(original, next), isFalse);
    });

    test(
      'the constructor copies its map so later external edits do not leak',
      () {
        final backing = {'sigA': entry('sigA')};
        final store = TriageStore(backing);
        backing['sigB'] = entry('sigB');
        expect(store.entryFor('sigB'), isNull);
      },
    );
  });

  group('lifecycle: recordSeen (fresh → known on save)', () {
    test('a first-seen signature is stamped KNOWN with firstSeen=now', () {
      final promoted = TriageStore.empty.recordSeen(['sigA'], t1);
      final e = promoted.entryFor('sigA');
      expect(e, isNotNull);
      expect(e!.status, TriageStatus.known);
      expect(e.firstSeen, t1);
    });

    test('models "NEW this session, KNOWN next session"', () {
      // Session 1: empty baseline, sigA visible → NEW.
      const baseline = TriageStore.empty;
      expect(baseline.displayFor(['sigA'])['sigA'], TriageDisplay.fresh);
      // On save, sigA is folded in as KNOWN and written to disk.
      final promoted = baseline.recordSeen(['sigA'], t0);
      // Session 2 loads the promoted store: sigA now reads KNOWN.
      expect(promoted.displayFor(['sigA'])['sigA'], TriageDisplay.known);
    });

    test('never downgrades an ACK and preserves the original firstSeen', () {
      final store = TriageStore.empty.upsert(
        entry('sigA', status: TriageStatus.acknowledged, firstSeen: t0),
      );
      final promoted = store.recordSeen(['sigA'], t1);
      final e = promoted.entryFor('sigA')!;
      expect(e.status, TriageStatus.acknowledged);
      expect(e.firstSeen, t0);
    });
  });

  group('acknowledge', () {
    test('marks acknowledged with a note, stamping firstSeen when new', () {
      final store = TriageStore.empty.acknowledge(
        'sigA',
        note: 'TICKET-1',
        now: t1,
      );
      final e = store.entryFor('sigA')!;
      expect(e.status, TriageStatus.acknowledged);
      expect(e.note, 'TICKET-1');
      expect(e.firstSeen, t1);
    });

    test('preserves the original firstSeen when the signature is known', () {
      final store = TriageStore.empty
          .upsert(entry('sigA', firstSeen: t0))
          .acknowledge('sigA', note: 'later', now: t1);
      expect(store.entryFor('sigA')!.firstSeen, t0);
    });

    test('a null note keeps any existing note', () {
      final store = TriageStore.empty
          .acknowledge('sigA', note: 'keep me', now: t0)
          .acknowledge('sigA', now: t1);
      expect(store.entryFor('sigA')!.note, 'keep me');
    });
  });

  group('JSON round-trip', () {
    test('TriageEntry with a note survives to/from JSON', () {
      final e = entry('sigA', status: TriageStatus.acknowledged, note: 'BUG-9');
      expect(TriageEntry.fromJson(e.toJson()), e);
    });

    test('TriageStore round-trips its entries', () {
      final store = TriageStore.empty
          .upsert(entry('a', note: 'n'))
          .upsert(entry('b', status: TriageStatus.acknowledged));
      expect(TriageStore.fromJson(store.toJson()), store);
    });

    test('an empty entries payload decodes to an empty store', () {
      expect(TriageStore.fromJson(const {}), TriageStore.empty);
    });
  });
}
