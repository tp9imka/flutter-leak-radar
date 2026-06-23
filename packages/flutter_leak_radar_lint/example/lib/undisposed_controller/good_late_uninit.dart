// example/lib/undisposed_controller/good_late_uninit.dart
// Proves: a `late` field with no initializer in either the declaration
// or initState is NOT flagged (not proven owned by this State).
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // `late` with no initializer and not assigned in initState.
  // The rule must stay silent here.
  late TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
