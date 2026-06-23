// example/lib/unclosed_stream_controller/good.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

// Good: controller closed in dispose().
class _MyWidgetState extends State<MyWidget> {
  final _controller = StreamController<int>();

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
