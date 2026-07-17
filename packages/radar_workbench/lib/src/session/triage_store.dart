import 'package:radar_ui/radar_ui.dart' show TriageDisplay;

/// Persisted cross-session triage status of a leak-cluster signature.
///
/// GONE is deliberately absent: it is not a stored state but a *computed* one —
/// a known signature that has disappeared from the current cluster set (a fix
/// landed). See [TriageStore.displayFor].
enum TriageStatus { fresh, known, acknowledged }

/// Maps a persisted [TriageStatus] to its display bucket. GONE is never
/// produced here — it is derived by [TriageStore.displayFor] from absence.
TriageDisplay _displayForStatus(TriageStatus status) => switch (status) {
  TriageStatus.fresh => TriageDisplay.fresh,
  TriageStatus.known => TriageDisplay.known,
  TriageStatus.acknowledged => TriageDisplay.acknowledged,
};

/// One cross-session record for a leak-cluster [signature]: when it was first
/// seen, its triage [status], and an optional user [note] (captured on ACK).
final class TriageEntry {
  const TriageEntry({
    required this.signature,
    required this.firstSeen,
    required this.status,
    this.note,
  });

  /// The cluster path signature (`pathSignature`) this record identifies.
  /// Byte-stable across sessions — the anchor of cross-session identity.
  final String signature;

  /// Wall-clock time the signature was first recorded, from the injected clock.
  final DateTime firstSeen;

  final TriageStatus status;

  /// Free-text note attached when the user acknowledges the leak. Null when
  /// none was given.
  final String? note;

  factory TriageEntry.fromJson(Map<String, Object?> json) => TriageEntry(
    signature: json['signature'] as String,
    firstSeen: DateTime.parse(json['firstSeen'] as String),
    status: TriageStatus.values.byName(json['status'] as String),
    note: json['note'] as String?,
  );

  Map<String, Object?> toJson() => {
    'signature': signature,
    'firstSeen': firstSeen.toIso8601String(),
    'status': status.name,
    if (note != null) 'note': note,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriageEntry &&
          signature == other.signature &&
          firstSeen == other.firstSeen &&
          status == other.status &&
          note == other.note;

  @override
  int get hashCode => Object.hash(signature, firstSeen, status, note);
}

/// Immutable set of [TriageEntry] records keyed by signature, persisted inside
/// a session so leak identity survives across days ("NEW / KNOWN / ACK /
/// GONE"). Every mutation returns a new store.
final class TriageStore {
  /// Wraps an explicit entry map. Copies into an unmodifiable map so callers
  /// cannot mutate the store's backing store after construction.
  TriageStore(Map<String, TriageEntry> entries)
    : _entries = Map.unmodifiable(entries);

  const TriageStore._(this._entries);

  /// The empty store — no cross-session history yet. A const so it can seed a
  /// default [PersistedSession] field.
  static const TriageStore empty = TriageStore._(<String, TriageEntry>{});

  final Map<String, TriageEntry> _entries;

  /// The record for [signature], or null when it has never been seen.
  TriageEntry? entryFor(String signature) => _entries[signature];

  /// All records, unordered. Read-only.
  Iterable<TriageEntry> get entries => _entries.values;

  /// Returns a new store with [entry] inserted or replacing the record for its
  /// signature.
  TriageStore upsert(TriageEntry entry) =>
      TriageStore({..._entries, entry.signature: entry});

  /// Chips for the current cluster list vs the stored history. For every
  /// signature in [currentSignatures]: no entry → [TriageDisplay.fresh] (NEW);
  /// an entry → its stored status (KNOWN / ACK). For every stored entry whose
  /// signature is *absent* from [currentSignatures] → [TriageDisplay.gone] (a
  /// fix landed). GONE always wins over a stored status because it is computed
  /// from absence.
  ///
  /// The returned map is keyed by the union of [currentSignatures] and the
  /// store's signatures, so GONE rows (which have no current cluster) are
  /// reachable by callers rendering the "fixed since last session" section.
  Map<String, TriageDisplay> displayFor(Iterable<String> currentSignatures) {
    final current = currentSignatures.toSet();
    final result = <String, TriageDisplay>{};
    for (final signature in current) {
      final entry = _entries[signature];
      result[signature] = entry == null
          ? TriageDisplay.fresh
          : _displayForStatus(entry.status);
    }
    for (final entry in _entries.values) {
      if (!current.contains(entry.signature)) {
        result[entry.signature] = TriageDisplay.gone;
      }
    }
    return result;
  }

  /// Folds [currentSignatures] into the store as KNOWN for the *next* session,
  /// stamping [now] as `firstSeen` for signatures never seen before. Existing
  /// records keep their status (ACK is never downgraded) and their original
  /// `firstSeen`.
  ///
  /// This is the "on session save" promotion. It is applied to the copy written
  /// to disk — the in-session store the views compare against is left as the
  /// loaded baseline, so a signature stays NEW for the whole current session
  /// and only reads as KNOWN when a *later* session loads this store.
  TriageStore recordSeen(Iterable<String> currentSignatures, DateTime now) {
    final next = {..._entries};
    for (final signature in currentSignatures) {
      next[signature] ??= TriageEntry(
        signature: signature,
        firstSeen: now,
        status: TriageStatus.known,
      );
    }
    return TriageStore(next);
  }

  /// Explicit user action: marks [signature] acknowledged with an optional
  /// [note]. Preserves the original `firstSeen` when the signature is already
  /// known, else stamps [now]. A null [note] keeps any existing note.
  TriageStore acknowledge(
    String signature, {
    String? note,
    required DateTime now,
  }) {
    final existing = _entries[signature];
    return upsert(
      TriageEntry(
        signature: signature,
        firstSeen: existing?.firstSeen ?? now,
        status: TriageStatus.acknowledged,
        note: note ?? existing?.note,
      ),
    );
  }

  factory TriageStore.fromJson(Map<String, Object?> json) {
    final entries = <String, TriageEntry>{};
    for (final e in (json['entries'] as List? ?? const [])) {
      final entry = TriageEntry.fromJson((e as Map).cast<String, Object?>());
      entries[entry.signature] = entry;
    }
    return TriageStore(entries);
  }

  Map<String, Object?> toJson() => {
    'entries': [for (final e in _entries.values) e.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriageStore && _mapEquals(_entries, other._entries);

  @override
  int get hashCode => Object.hashAllUnordered(_entries.values);
}

bool _mapEquals(Map<String, TriageEntry> a, Map<String, TriageEntry> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}
