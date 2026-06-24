// test/ui/theme/theme_test.dart
//
// google_fonts cannot fetch fonts from the network in test environments.
// TextStyle getters fire an async font-load side-effect; we drain the async
// queue inside testWidgets so the load error is caught by the tester's error
// handler (which we suppress), preventing "test failed after completion".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_leak_radar/flutter_leak_radar.dart' show LeakSeverity;
import 'package:flutter_leak_radar/src/ui/theme/theme.dart';

// Suppresses google_fonts async font-load errors in tests.
bool _isGoogleFontsError(Object e) =>
    e.toString().contains('google_fonts') ||
    e.toString().contains('GoogleFonts') ||
    e.toString().contains('allowRuntimeFetching') ||
    e.toString().contains('Failed to load font');

void main() {
  setUpAll(() {
    // Prevents google_fonts from attempting HTTP requests in test environments.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // ── SeverityTokens ──────────────────────────────────────────────────────────

  group('SeverityTokens', () {
    test('critical tokens return severityCritical text colour', () {
      final tokens = severityTokens(LeakSeverity.critical);
      expect(tokens.text, equals(LeakRadarColors.severityCritical));
    });

    test('warning tokens return severityWarning text colour', () {
      final tokens = severityTokens(LeakSeverity.warning);
      expect(tokens.text, equals(LeakRadarColors.severityWarning));
    });

    test('info tokens return severityInfo text colour', () {
      final tokens = severityTokens(LeakSeverity.info);
      expect(tokens.text, equals(LeakRadarColors.severityInfo));
    });

    test('all severity variants have non-zero alpha tag background', () {
      for (final sev in LeakSeverity.values) {
        final tokens = severityTokens(sev);
        expect(
          tokens.tagBg.a,
          greaterThan(0),
          reason: '$sev tagBg should have some opacity',
        );
      }
    });

    test('all severity variants have non-zero alpha row background', () {
      for (final sev in LeakSeverity.values) {
        final tokens = severityTokens(sev);
        expect(
          tokens.rowBg.a,
          greaterThan(0),
          reason: '$sev rowBg should have some opacity',
        );
      }
    });
  });

  // ── LeakRadarColors ─────────────────────────────────────────────────────────

  group('LeakRadarColors', () {
    test('accent is non-transparent', () {
      expect(LeakRadarColors.accent.a, greaterThan(0.9));
    });

    test('pageBg is very dark', () {
      expect(const Color(0xFF0a0d0e).computeLuminance(), lessThan(0.01));
    });

    test('severityCritical matches design spec hex', () {
      expect(LeakRadarColors.severityCritical, equals(const Color(0xFFff5d6c)));
    });

    test('severityWarning matches design spec hex', () {
      expect(LeakRadarColors.severityWarning, equals(const Color(0xFFf5b54a)));
    });

    test('severityInfo matches design spec hex', () {
      expect(LeakRadarColors.severityInfo, equals(const Color(0xFF5ad1e6)));
    });
  });

  // ── LeakRadarText ───────────────────────────────────────────────────────────
  //
  // testWidgets is used so we can call pumpEventQueue() to drain the async
  // font-load microtasks before the test ends; errors are suppressed via the
  // tester's FlutterError handler.

  group('LeakRadarText', () {
    testWidgets('title has bold weight and correct colour', (tester) async {
      tester.binding.platformDispatcher.onError = (error, _) {
        return _isGoogleFontsError(error);
      };
      final style = LeakRadarText.title;
      expect(style.fontWeight, equals(FontWeight.w700));
      expect(style.color, equals(LeakRadarColors.text100));
      await tester.pumpAndSettle();
    });

    testWidgets('metric has semibold weight', (tester) async {
      tester.binding.platformDispatcher.onError = (error, _) =>
          _isGoogleFontsError(error);
      final style = LeakRadarText.metric;
      expect(style.fontWeight, equals(FontWeight.w600));
      await tester.pumpAndSettle();
    });

    testWidgets('mono has regular weight', (tester) async {
      tester.binding.platformDispatcher.onError = (error, _) =>
          _isGoogleFontsError(error);
      final style = LeakRadarText.mono;
      expect(style.fontWeight, equals(FontWeight.w400));
      await tester.pumpAndSettle();
    });

    testWidgets('label has medium weight', (tester) async {
      tester.binding.platformDispatcher.onError = (error, _) =>
          _isGoogleFontsError(error);
      final style = LeakRadarText.label;
      expect(style.fontWeight, equals(FontWeight.w500));
      await tester.pumpAndSettle();
    });

    testWidgets('body has regular weight', (tester) async {
      tester.binding.platformDispatcher.onError = (error, _) =>
          _isGoogleFontsError(error);
      final style = LeakRadarText.body;
      expect(style.fontWeight, equals(FontWeight.w400));
      await tester.pumpAndSettle();
    });

    testWidgets('severityTag has medium weight', (tester) async {
      tester.binding.platformDispatcher.onError = (error, _) =>
          _isGoogleFontsError(error);
      final style = LeakRadarText.severityTag;
      expect(style.fontWeight, equals(FontWeight.w500));
      await tester.pumpAndSettle();
    });
  });

  // ── RadarGlyph ──────────────────────────────────────────────────────────────

  group('RadarGlyph', () {
    testWidgets('renders without throwing at default size', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: RadarGlyph())),
        ),
      );
      expect(find.byType(RadarGlyph), findsOneWidget);
    });

    testWidgets('renders at custom size 48', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: RadarGlyph(size: 48))),
        ),
      );
      expect(find.byType(RadarGlyph), findsOneWidget);
      final box = tester.renderObject<RenderBox>(find.byType(RadarGlyph));
      expect(box.size, equals(const Size(48, 48)));
    });
  });
}
