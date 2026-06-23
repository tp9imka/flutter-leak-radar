// example/lib/undisposed_controller/good_late_field.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

// Good: late field with no initializer and not assigned in initState.
// The controller is not provably owned by this State.
class _MyWidgetState extends State<MyWidget> {
  late TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
