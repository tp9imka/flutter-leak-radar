// example/lib/undisposed_controller/good.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

// Good: constructor-param controller (not owned by State).
class _ParamState extends State<MyWidget> {
  _ParamState(this._controller);
  final TextEditingController _controller;

  @override
  Widget build(BuildContext context) => const SizedBox();
}
