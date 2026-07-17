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
/// seen, its triage [status], an optional user [note] (captured on ACK), the
/// [className] it last headlined (so a GONE row can name what was fixed), and
/// [goneSince] — the time it was first observed absent from the heap.
final class TriageEntry {
  const TriageEntry({
    required this.signature,
    required this.firstSeen,
    required this.status,
    this.note,
    this.className,
    this.goneSince,
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

  /// The class name this signature last headlined. Null for records written
  /// before class names were captured (tolerant migration).
  final String? className;

  /// When the signature was first observed missing from the current heap
  /// (a fix landed). Null while it is still present. Stamped once on save and
  /// cleared if the signature reappears (a regression).
  final DateTime? goneSince;

  TriageEntry copyWith({
    DateTime? firstSeen,
    TriageStatus? status,
    String? note,
    String? className,
    DateTime? goneSince,
    bool clearGoneSince = false,
  }) => TriageEntry(
    signature: signature,
    firstSeen: firstSeen ?? this.firstSeen,
    status: status ?? this.status,
    note: note ?? this.note,
    className: className ?? this.className,
    goneSince: clearGoneSince ? null : (goneSince ?? this.goneSince),
  );

  factory TriageEntry.fromJson(Map<String, Object?> json) => TriageEntry(
    signature: json['signature'] as String,
    firstSeen: DateTime.parse(json['firstSeen'] as String),
    status: TriageStatus.values.byName(json['status'] as String),
    note: json['note'] as String?,
    className: json['className'] as String?,
    goneSince: json['goneSince'] == null
        ? null
        : DateTime.parse(json['goneSince'] as String),
  );

  Map<String, Object?> toJson() => {
    'signature': signature,
    'firstSeen': firstSeen.toIso8601String(),
    'status': status.name,
    if (note != null) 'note': note,
    if (className != null) 'className': className,
    if (goneSince != null) 'goneSince': goneSince!.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriageEntry &&
          signature == other.signature &&
          firstSeen == other.firstSeen &&
          status == other.status &&
          note == other.note &&
          className == other.className &&
          goneSince == other.goneSince;

  @override
  int get hashCode =>
      Object.hash(signature, firstSeen, status, note, className, goneSince);
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

  /// Folds the current heap into the store for the *next* session. Given
  /// [classNameBySignature] (the signatures visible now, each mapped to the
  /// class it headlines) and [now]:
  ///
  /// - a signature never seen before is recorded KNOWN with `firstSeen = now`;
  /// - an existing entry that is present again has its `goneSince` cleared (a
  ///   regression resurfaces as KNOWN/ACK) and its `className` refreshed, while
  ///   its status and original `firstSeen` are preserved (ACK is never
  ///   downgraded);
  /// - an existing entry that is absent has `goneSince` stamped once (never
  ///   re-stamped), leaving it otherwise untouched.
  ///
  /// Applied to the persisted copy, not the in-session store the views read —
  /// see [SessionPersistence]. Callers MUST NOT invoke this when the current
  /// signature set is unknown (no focused snapshot): an empty map would mark
  /// every entry gone.
  TriageStore foldSeen(Map<String, String> classNameBySignature, DateTime now) {
    final current = classNameBySignature.keys.toSet();
    final next = <String, TriageEntry>{};
    for (final entry in _entries.values) {
      if (current.contains(entry.signature)) {
        next[entry.signature] = entry.copyWith(
          clearGoneSince: true,
          className: classNameBySignature[entry.signature],
        );
      } else {
        next[entry.signature] = entry.goneSince == null
            ? entry.copyWith(goneSince: now)
            : entry;
      }
    }
    for (final e in classNameBySignature.entries) {
      next.putIfAbsent(
        e.key,
        () => TriageEntry(
          signature: e.key,
          firstSeen: now,
          status: TriageStatus.known,
          className: e.value,
        ),
      );
    }
    return TriageStore(next);
  }

  /// Folds the acknowledged entries of [source] into this store, preserving
  /// this store's `firstSeen` / `goneSince` where they already exist. Used to
  /// carry ACKs made on the in-session display store into the persisted copy.
  TriageStore overlayAcks(TriageStore source) {
    final next = {..._entries};
    for (final e in source._entries.values) {
      if (e.status != TriageStatus.acknowledged) continue;
      final existing = next[e.signature];
      next[e.signature] = TriageEntry(
        signature: e.signature,
        firstSeen: existing?.firstSeen ?? e.firstSeen,
        status: TriageStatus.acknowledged,
        note: e.note ?? existing?.note,
        className: e.className ?? existing?.className,
        goneSince: existing?.goneSince,
      );
    }
    return TriageStore(next);
  }

  /// Explicit user action: marks [signature] acknowledged with an optional
  /// [note]. Preserves the original `firstSeen`, `className`, and `goneSince`
  /// when the signature is already known, else stamps [now]. A null [note]
  /// keeps any existing note.
  TriageStore acknowledge(
    String signature, {
    String? note,
    String? className,
    required DateTime now,
  }) {
    final existing = _entries[signature];
    return upsert(
      TriageEntry(
        signature: signature,
        firstSeen: existing?.firstSeen ?? now,
        status: TriageStatus.acknowledged,
        note: note ?? existing?.note,
        className: className ?? existing?.className,
        goneSince: existing?.goneSince,
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

/// The store to persist for the next session, shared by both hosts.
///
/// Starts from [diskStore] (the accumulating on-disk mirror — pins `firstSeen`),
/// overlays ACKs from [displayStore] (the in-session store the views mutate),
/// then folds the current heap in when [classNameBySignature] is non-null.
///
/// [classNameBySignature] is `null` when there is no focused snapshot — the
/// current signature set is UNKNOWN, so the fold is skipped entirely (folding
/// an empty map would wrongly mark every entry gone). An empty map is distinct:
/// it means the focused snapshot genuinely has no leak clusters, so every known
/// signature is legitimately gone.
TriageStore foldSessionTriage({
  required TriageStore diskStore,
  required TriageStore displayStore,
  required Map<String, String>? classNameBySignature,
  required DateTime now,
}) {
  final withAcks = diskStore.overlayAcks(displayStore);
  return classNameBySignature == null
      ? withAcks
      : withAcks.foldSeen(classNameBySignature, now);
}
