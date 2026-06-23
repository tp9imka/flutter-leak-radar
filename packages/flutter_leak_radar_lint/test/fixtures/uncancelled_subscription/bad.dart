// test/fixtures/uncancelled_subscription/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  // expect_lint: uncancelled_subscription
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
  // Missing dispose() with _sub?.cancel().
}
