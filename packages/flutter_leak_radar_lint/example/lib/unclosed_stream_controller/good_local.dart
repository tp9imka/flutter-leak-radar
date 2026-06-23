// example/lib/unclosed_stream_controller/good_local.dart
// Proves: a StreamController local variable (not a field) is NOT flagged — the
// rule only tracks fields owned by the State/Bloc lifecycle.
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    // ignore: unused_local_variable
    final controller = StreamController<int>();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
