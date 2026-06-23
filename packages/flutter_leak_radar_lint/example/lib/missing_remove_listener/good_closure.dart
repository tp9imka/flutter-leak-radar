// example/lib/missing_remove_listener/good_closure.dart
// Proves the conservative design: an inline-closure listener has no
// referenceable identity to pair against, so it is NEVER flagged (false
// negative by design — the runtime package backstops this shape).
import 'package:flutter/widgets.dart';

class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  final ValueNotifier<int> _notifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _notifier.addListener(() {});
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
