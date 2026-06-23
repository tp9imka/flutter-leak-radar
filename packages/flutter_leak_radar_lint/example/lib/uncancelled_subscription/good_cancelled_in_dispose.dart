// example/lib/uncancelled_subscription/good_cancelled_in_dispose.dart
import 'dart:async';
import 'package:flutter/widgets.dart';

class MyWidget2 extends StatefulWidget {
  const MyWidget2({super.key});
  @override
  State<MyWidget2> createState() => _MyWidget2State();
}

// Cascade form: _sub..cancel() is also recognised.
class _MyWidget2State extends State<MyWidget2> {
  StreamSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Stream.periodic(const Duration(seconds: 1)).listen((_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
