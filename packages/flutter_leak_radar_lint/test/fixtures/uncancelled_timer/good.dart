// test/fixtures/uncancelled_timer/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _GoodState extends State<StatefulWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Cancelled inside an if-block — also valid; disposedInTeardown is recursive.
class _GoodConditionalCancelState extends State<StatefulWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    if (_timer != null) {
      _timer?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Cancelled inside a try/finally block — also valid.
class _GoodTryCancelState extends State<StatefulWidget> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  void dispose() {
    try {
      _timer?.cancel();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Local-variable timer (fire-and-forget) — never stored in a field; not flagged.
class _LocalTimerState extends State<StatefulWidget> {
  @override
  void initState() {
    super.initState();
    // ignore: unused_local_variable
    Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Constructor-injected timer via field-formal (this._timer) — externally owned;
// must NOT be flagged.
class _GoodFieldFormalTimerState extends State<StatefulWidget> {
  _GoodFieldFormalTimerState(this._timer);
  final Timer _timer;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
