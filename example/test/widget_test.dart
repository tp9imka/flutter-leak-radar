// test/widget_test.dart
//
// Smoke tests for the Radar Showcase example app.
//
// The full app requires Radar.init() which touches dart:vm services and the
// platform channel. Tests use a minimal stub tree that bypasses init() so
// they run on any host (CI, no device required).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_leak_radar_example/showcase/showcase_home.dart';

/// Minimal harness — skips Radar.init(); mounts ShowcaseHome directly.
Widget _buildTestApp() {
  return MaterialApp(
    home: ShowcaseHome(
      leakyScreenBuilder: () => const Scaffold(body: Text('leaky')),
      leakyBlocScreenBuilder: () => const Scaffold(body: Text('leaky bloc')),
      onSelfTest: (_) async {},
    ),
  );
}

void main() {
  testWidgets('showcase home renders visible section headers and tiles', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pump();

    // The LEAKS section and first three tiles are within the default 600px
    // test viewport — verify they render.
    expect(find.text('LEAKS'), findsOneWidget);
    expect(find.text('Leaky screen (patterns 1–6)'), findsOneWidget);
    expect(find.text('Leaky Bloc screen (pattern 7)'), findsOneWidget);
    expect(find.text('Properly disposed screen (contrast)'), findsOneWidget);

    // Scroll to reveal the perf sections.
    await tester.scrollUntilVisible(
      find.text('PERF · TRACING'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('PERF · TRACING'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('PERF · REBUILDS'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('PERF · REBUILDS'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('STABILITY · ERRORS'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('STABILITY · ERRORS'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('STABILITY · STALLS'),
      200,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('STABILITY · STALLS'), findsOneWidget);
  });

  testWidgets('inspector button is present and opens RadarScreen', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pump();

    final inspectorBtn = find.byKey(const Key('open_radar_screen'));
    expect(inspectorBtn, findsOneWidget);

    await tester.tap(inspectorBtn);
    await tester.pumpAndSettle();

    // RadarScreen has a tab bar with Leaks and Performance tabs.
    expect(find.text('Leaks'), findsWidgets);
    expect(find.text('Performance'), findsWidgets);
  });

  testWidgets('leaky screen tile navigates to leaky stub', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pump();

    // The tile is always on-screen (first in the list).
    await tester.tap(find.text('Leaky screen (patterns 1–6)'));
    await tester.pumpAndSettle();

    expect(find.text('leaky'), findsOneWidget);
  });
}
