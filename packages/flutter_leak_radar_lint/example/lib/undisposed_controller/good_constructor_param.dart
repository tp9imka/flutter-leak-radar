// example/lib/undisposed_controller/good_constructor_param.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

// Good: controller passed in via constructor — not owned by this State.
class _MyWidgetState extends State<MyWidget> {
  _MyWidgetState(this._controller);
  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
