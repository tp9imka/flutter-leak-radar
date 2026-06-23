// test/fixtures/uncancelled_subscription/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _GoodState extends State<StatefulWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Cancelled inside an if-block — also valid; disposedInTeardown is recursive.
class _GoodConditionalCancelState extends State<StatefulWidget> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = const Stream<String>.empty().listen((_) {});
  }

  @override
  void dispose() {
    if (_sub != null) {
      _sub?.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Local-variable subscription — never stored in a field; not flagged.
class _LocalSubState extends State<StatefulWidget> {
  @override
  void initState() {
    super.initState();
    // ignore: unused_local_variable
    final sub = Stream.value(1).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
