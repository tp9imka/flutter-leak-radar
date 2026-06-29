// example/lib/showcase/showcase_home.dart
//
// Sectioned "Radar Showcase" home screen.
//
// Each section corresponds to one dashboard area. Tapping a section
// navigates to a focused demo screen that produces real data in that tab.
import 'package:flutter/material.dart';
import 'package:radar/radar.dart';

import 'good_screen.dart';
import 'perf_tracing_screen.dart';
import 'rebuild_demo_screen.dart';
import 'jank_demo_screen.dart';
import 'stability_error_screen.dart';
import 'stability_stall_screen.dart';

/// Root home for the Radar Showcase.
///
/// Accepts builder callbacks so [main.dart] keeps full control over which
/// concrete screens are used — this keeps [ShowcaseHome] testable without
/// real leak infrastructure.
class ShowcaseHome extends StatelessWidget {
  const ShowcaseHome({
    super.key,
    required this.leakyScreenBuilder,
    required this.leakyBlocScreenBuilder,
    required this.onSelfTest,
  });

  final Widget Function() leakyScreenBuilder;
  final Widget Function() leakyBlocScreenBuilder;
  final Future<void> Function(NavigatorState) onSelfTest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radar Showcase'),
        actions: [_InspectorButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Leaks'),
          _ShowcaseTile(
            icon: Icons.memory,
            title: 'Leaky screen (patterns 1–6)',
            subtitle:
                'Timer, subscription, controller, StreamController,'
                ' listen result, missing removeListener',
            onTap: () => _push(context, leakyScreenBuilder()),
          ),
          _ShowcaseTile(
            icon: Icons.memory_outlined,
            title: 'Leaky Bloc screen (pattern 7)',
            subtitle:
                'LeakyCubit — uncancelled StreamSubscription'
                ' (bloc_uncancelled_subscription)',
            onTap: () => _push(context, leakyBlocScreenBuilder()),
          ),
          _ShowcaseTile(
            icon: Icons.check_circle_outline,
            title: 'Properly disposed screen (contrast)',
            subtitle: 'Same resources — all disposed correctly, no findings',
            onTap: () => _push(context, const GoodScreen()),
          ),
          _ShowcaseTile(
            icon: Icons.play_arrow_outlined,
            title: 'Run leak self-test',
            subtitle:
                'Automated 6-cycle drive + forceGcAndScan → console summary',
            onTap: () => onSelfTest(Navigator.of(context)),
          ),
          const Divider(height: 24),
          _SectionHeader('Perf · Tracing'),
          _ShowcaseTile(
            icon: Icons.timeline,
            title: 'Sync + async span demo',
            subtitle:
                'Radar.trace / Radar.traceAsync — populates Spans tab'
                ' with real p50/p95/p99',
            onTap: () => _push(context, const PerfTracingScreen()),
          ),
          const Divider(height: 24),
          _SectionHeader('Perf · Rebuilds'),
          _ShowcaseTile(
            icon: Icons.refresh,
            title: 'TracedSubtree rebuild counter',
            subtitle: 'Ticking counter forces rebuilds — Rebuilds panel climbs',
            onTap: () => _push(context, const RebuildDemoScreen()),
          ),
          const Divider(height: 24),
          _SectionHeader('Perf · Frames / Jank'),
          _ShowcaseTile(
            icon: Icons.bar_chart,
            title: 'Real jank demo',
            subtitle:
                'Heavy synchronous work during build — Frames tab records'
                ' over-budget frames',
            onTap: () => _push(context, const JankDemoScreen()),
          ),
          const Divider(height: 24),
          _SectionHeader('Stability · Errors'),
          _ShowcaseTile(
            icon: Icons.bug_report_outlined,
            title: 'Trigger FlutterError',
            subtitle:
                'Throws inside a widget callback — caught by the framework'
                " error handler → Stability tab's error count climbs",
            onTap: () => _push(context, const StabilityErrorScreen()),
          ),
          const Divider(height: 24),
          _SectionHeader('Stability · Stalls'),
          _ShowcaseTile(
            icon: Icons.timer_off_outlined,
            title: 'Block main isolate',
            subtitle:
                'Busy-wait > stallThreshold (200ms) — stall watchdog fires'
                ' → Stability tab stall count climbs',
            onTap: () => _push(context, const StabilityStallScreen()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _InspectorButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('open_radar_screen'),
      icon: const Icon(Icons.radar),
      tooltip: 'Open Radar Dashboard',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const RadarScreen())),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ShowcaseTile extends StatelessWidget {
  const _ShowcaseTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}
