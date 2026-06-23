// example/lib/missing_remove_listener/good.dart
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

// Good: removeListener pairs the addListener with the same tear-off.
class _MyWidgetState extends State<MyWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onChange);
  }

  void _onChange() {}

  @override
  void dispose() {
    _notifier.removeListener(_onChange);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
