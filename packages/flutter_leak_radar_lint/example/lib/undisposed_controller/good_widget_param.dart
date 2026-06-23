// example/lib/undisposed_controller/good_widget_param.dart
// Proves: a controller passed to this widget via its StatefulWidget
// constructor is NOT flagged — the caller owns it, not this State.
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key, required this.controller});
  final TextEditingController controller;
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // Accessed via widget.controller — not created here, not owned here.
  @override
  Widget build(BuildContext context) => const SizedBox();
}
