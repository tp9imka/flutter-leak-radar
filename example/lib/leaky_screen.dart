import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_leak_radar/flutter_leak_radar.dart';

/// A screen that INTENTIONALLY leaks: it starts a periodic Timer and opens a
/// StreamController in initState but never cancels/closes them in dispose().
/// Each push/pop leaves the State (and its Timer) retained.
class LeakyScreen extends StatefulWidget {
  const LeakyScreen({super.key});
  @override
  State<LeakyScreen> createState() => _LeakyScreenState();
}

class _LeakyScreenState extends State<LeakyScreen> {
  // ignore: unused_field — intentional leak: _timer is never cancelled
  late final Timer _timer;
  final StreamController<int> _controller = StreamController<int>.broadcast();

  @override
  void initState() {
    super.initState();
    LeakRadar.track(this, tag: 'LeakyScreenState'); // precise opt-in
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _controller.add(0));
  }

  // BUG ON PURPOSE: no dispose() cancelling _timer / closing _controller,
  // and no LeakRadar.markDisposed(this).

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Leaky screen')),
        body: const Center(child: Text('Pop me, then Scan in Leak Radar.')),
      );
}
