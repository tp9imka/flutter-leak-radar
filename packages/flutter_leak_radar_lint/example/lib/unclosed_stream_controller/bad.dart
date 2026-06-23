// example/lib/unclosed_stream_controller/bad.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // expect_lint: unclosed_stream_controller
  final _controller = StreamController<int>();

  @override
  Widget build(BuildContext context) => const SizedBox();
  // Missing dispose() with _controller.close().
}
