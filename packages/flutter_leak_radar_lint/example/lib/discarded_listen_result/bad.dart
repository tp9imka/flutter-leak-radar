// example/lib/discarded_listen_result/bad.dart
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
    // expect_lint: discarded_listen_result
    Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
