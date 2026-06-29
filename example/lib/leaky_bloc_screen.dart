// example/lib/leaky_bloc_screen.dart
//
// Screen that creates a LeakyCubit — triggers pattern 7 at runtime.
import 'package:flutter/material.dart';
import 'package:radar/radar.dart';

import 'leaky_cubit.dart';

class LeakyBlocScreen extends StatefulWidget {
  const LeakyBlocScreen({super.key});

  @override
  State<LeakyBlocScreen> createState() => _LeakyBlocScreenState();
}

class _LeakyBlocScreenState extends State<LeakyBlocScreen> {
  late final LeakyCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = LeakyCubit();
    Radar.track(_cubit, tag: 'LeakyCubit');
  }

  @override
  void dispose() {
    // Tell Radar the Cubit should now be collectable. We intentionally do NOT
    // call _cubit.close(), so its uncancelled StreamSubscription keeps the
    // Cubit alive after this screen is popped — the precise tracker then
    // reports it as a notGced leak.
    Radar.markDisposed(_cubit);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Leaky Bloc Screen — pattern 7')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StreamBuilder<int>(
              stream: _cubit.stream,
              initialData: _cubit.state,
              builder: (context, snapshot) => Text(
                'Cubit state: ${snapshot.data}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This screen leaks:\n'
              '  7. LeakyCubit has an uncancelled StreamSubscription\n'
              '     (bloc_uncancelled_subscription)\n\n'
              'Pop this screen to trigger a navigation scan,\n'
              'then check the Radar dashboard.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
