// test/fixtures/uncancelled_timer/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadPeriodicState extends State<StatefulWidget> {
  // expect_lint: uncancelled_timer
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
  // Missing dispose() with _timer?.cancel().
}
