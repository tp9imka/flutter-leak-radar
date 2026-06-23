// example/lib/undisposed_controller/bad.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // expect_lint: undisposed_controller
  final _controller = TextEditingController();

  @override
  Widget build(BuildContext context) => const SizedBox();
  // No dispose() override — lint should fire.
}
