// test/fixtures/unclosed_stream_controller/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class _BadState extends State<StatefulWidget> {
  // expect_lint: unclosed_stream_controller
  final _controller = StreamController<int>();

  @override
  Widget build(BuildContext context) => const SizedBox();
  // Missing dispose() with _controller.close().
}

// Broadcast controller, dispose() exists but does not close the controller.
class _BadBroadcastState extends State<StatefulWidget> {
  // expect_lint: unclosed_stream_controller
  final StreamController<String> _events = StreamController<String>.broadcast();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
