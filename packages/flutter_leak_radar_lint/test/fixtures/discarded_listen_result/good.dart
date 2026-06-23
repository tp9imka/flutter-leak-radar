// test/fixtures/discarded_listen_result/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _GoodState extends State<StatefulWidget> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    // Good: result captured in a field.
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

// Good: listen result assigned to a local variable
// (still a potential leak but not the discarded shape this rule targets).
void notAWidget() {
  final sub = Stream<int>.empty().listen((_) {});
  sub.cancel();
}
