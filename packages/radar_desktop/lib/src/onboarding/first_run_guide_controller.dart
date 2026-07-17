import 'dart:async';

import 'package:flutter/foundation.dart';

import 'first_run_store.dart';

export 'first_run_store.dart';

/// Owns the once-only, skippable, re-openable first-run tour state.
///
/// `step`: 0 welcome · 1..[lastSpotlight] spotlights · 6 finish.
/// [load] reads the persisted seen flag and auto-opens at the welcome
/// step when unseen; [next]/[back] walk the steps; [skip]/[complete]
/// close the guide and persist the seen flag; [reopen] re-shows the
/// welcome step without touching the seen flag.
final class FirstRunGuideController extends ChangeNotifier {
  FirstRunGuideController({FirstRunStore store = const FileFirstRunStore()})
    : _store = store;

  /// Steps 1..[lastSpotlight] are the rail/connect-bar spotlights.
  static const int lastSpotlight = 5;

  static const int _welcomeStep = 0;
  static const int _finishStep = lastSpotlight + 1;

  final FirstRunStore _store;

  int _step = _welcomeStep;
  bool _open = false;
  bool _seen = false;

  /// Guards [_notify] against firing after [dispose] — [skip] and
  /// [complete] fire-and-forget [FirstRunStore.markSeen], which may
  /// still resolve after the controller (and its listening widget) has
  /// been torn down.
  bool _disposed = false;

  /// The current step: 0 welcome, 1..[lastSpotlight] spotlights, 6 finish.
  int get step => _step;

  /// Whether the guide overlay should currently be shown.
  bool get open => _open;

  /// Whether the guide has been completed or skipped at least once.
  bool get seen => _seen;

  /// Reads the persisted seen flag and auto-opens at the welcome step
  /// when the guide hasn't been seen yet. Never throws — a missing or
  /// unreadable store reads as "not seen".
  Future<void> load() async {
    _seen = await _store.hasSeen();
    if (!_seen) {
      _open = true;
      _step = _welcomeStep;
    }
    _notify();
  }

  /// Advances to the next step. From the finish step, this instead
  /// [complete]s the guide.
  void next() {
    if (_step >= _finishStep) {
      complete();
      return;
    }
    _step++;
    _notify();
  }

  /// Steps back, flooring at the welcome step.
  void back() {
    if (_step <= _welcomeStep) return;
    _step--;
    _notify();
  }

  /// Closes the guide and marks it seen without finishing the tour —
  /// the ✕ / Skip / Esc / backdrop-click paths.
  void skip() => _closeAndMarkSeen();

  /// Closes the guide and marks it seen after finishing the tour — the
  /// Done button on the finish step.
  void complete() => _closeAndMarkSeen();

  void _closeAndMarkSeen() {
    _open = false;
    _seen = true;
    unawaited(_store.markSeen());
    _notify();
  }

  /// Re-shows the welcome step without touching the persisted seen flag
  /// — the `?` re-open button in the title bar.
  void reopen() {
    _open = true;
    _step = _welcomeStep;
    _notify();
  }

  /// Marks this controller disposed so an in-flight [load] or
  /// [FirstRunStore.markSeen] call cannot [notifyListeners] afterward.
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }
}
