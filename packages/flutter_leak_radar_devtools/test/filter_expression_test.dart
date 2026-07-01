import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_ui/radar_ui.dart';

import 'package:flutter_leak_radar_devtools/src/filter/filter_bar.dart';
import 'package:flutter_leak_radar_devtools/src/filter/filter_expression.dart';

// ── Test target ──────────────────────────────────────────────────────────

class _FakeTarget implements FilterTarget {
  const _FakeTarget(this.className, [this.libraryUri]);

  @override
  final String className;

  @override
  final Uri? libraryUri;
}

_FakeTarget _t(String className, [String? libraryUri]) =>
    _FakeTarget(className, libraryUri == null ? null : Uri.parse(libraryUri));

void main() {
  group('plain substring / field terms', () {
    test('bare word matches className substring, case-insensitively', () {
      final expr = FilterExpression.parse('Foo');
      expect(expr.matches(_t('MyFooWidget')), isTrue);
      expect(expr.matches(_t('myfoowidget')), isTrue);
      expect(expr.matches(_t('FOOWIDGET')), isTrue);
      expect(expr.matches(_t('Bar')), isFalse);
    });

    test('class: matches className', () {
      final expr = FilterExpression.parse('class:Foo');
      expect(expr.matches(_t('_FooState')), isTrue);
      expect(expr.matches(_t('Bar')), isFalse);
    });

    test('library: matches libraryUri substring, case-insensitively', () {
      final expr = FilterExpression.parse('library:app');
      expect(expr.matches(_t('X', 'package:app/foo.dart')), isTrue);
      expect(expr.matches(_t('X', 'package:APP/foo.dart')), isTrue);
      expect(expr.matches(_t('X', 'package:other/foo.dart')), isFalse);
    });

    test('lib: is an alias for library:', () {
      final expr = FilterExpression.parse('lib:app');
      expect(expr.matches(_t('X', 'package:app/foo.dart')), isTrue);
      expect(expr.matches(_t('X', 'package:other/foo.dart')), isFalse);
    });

    test('library: is false (not error) when libraryUri is null', () {
      final expr = FilterExpression.parse('library:app');
      expect(expr.matches(_t('X')), isFalse);
    });

    test('! negates a leaf term', () {
      final expr = FilterExpression.parse('!class:Foo');
      expect(expr.matches(_t('Foo')), isFalse);
      expect(expr.matches(_t('Bar')), isTrue);
    });
  });

  group('boolean composition', () {
    test('implicit && via whitespace requires all terms', () {
      final expr = FilterExpression.parse('class:App library:app');
      expect(expr.matches(_t('App', 'package:app/x.dart')), isTrue);
      expect(expr.matches(_t('App', 'package:other/x.dart')), isFalse);
      expect(expr.matches(_t('Other', 'package:app/x.dart')), isFalse);
    });

    test('explicit && behaves the same as implicit &&', () {
      final expr = FilterExpression.parse('class:App && library:app');
      expect(expr.matches(_t('App', 'package:app/x.dart')), isTrue);
      expect(expr.matches(_t('App', 'package:other/x.dart')), isFalse);
    });

    test('|| matches when either side matches', () {
      final expr = FilterExpression.parse('class:App || class:Bar');
      expect(expr.matches(_t('App')), isTrue);
      expect(expr.matches(_t('Bar')), isTrue);
      expect(expr.matches(_t('Baz')), isFalse);
    });

    test('precedence: a || b && c parses as a || (b && c)', () {
      final expr = FilterExpression.parse(
        'class:Alpha || class:Bravo && class:Charlie',
      );
      // Alpha alone: a=true, b=false, c=false.
      // Correct (a || (b&&c)) => true. Wrong ((a||b)&&c) => false.
      expect(expr.matches(_t('Alpha')), isTrue);
      // Bravo+Charlie: a=false, b=true, c=true => true either way.
      expect(expr.matches(_t('Bravo Charlie')), isTrue);
      // Bravo alone: a=false, b=true, c=false => false either way.
      expect(expr.matches(_t('Bravo')), isFalse);
      // none: all false.
      expect(expr.matches(_t('Zzz')), isFalse);
    });

    test('parentheses override default precedence', () {
      final expr = FilterExpression.parse(
        '(class:Alpha || class:Bravo) && class:Charlie',
      );
      expect(expr.matches(_t('Alpha Charlie')), isTrue);
      // Without the parens this would match (a||(b&&c) = true), but
      // the parens force Charlie to be required.
      expect(expr.matches(_t('Alpha')), isFalse);
    });

    test('quoted values allow spaces', () {
      final fieldExpr = FilterExpression.parse('class:"Foo Bar"');
      expect(fieldExpr.matches(_t('Foo Bar Widget')), isTrue);
      expect(fieldExpr.matches(_t('FooBar')), isFalse);

      final bareExpr = FilterExpression.parse('"Foo Bar"');
      expect(bareExpr.matches(_t('Foo Bar Widget')), isTrue);
    });
  });

  group('malformed input degrades to matches-all', () {
    test('unbalanced open paren', () {
      final expr = FilterExpression.parse('(class:a');
      expect(expr.error, isNotNull);
      expect(expr.chips, isEmpty);
      expect(expr.matches(_t('anything')), isTrue);
    });

    test('dangling && with nothing after it', () {
      final expr = FilterExpression.parse('class:a &&');
      expect(expr.error, isNotNull);
      expect(expr.matches(_t('anything')), isTrue);
    });

    test('bare operator with no operands', () {
      final expr = FilterExpression.parse('&&');
      expect(expr.error, isNotNull);
      expect(expr.matches(_t('anything')), isTrue);
    });

    test('parsing malformed input never throws', () {
      for (final input in [
        '(class:a',
        'class:a &&',
        '&&',
        '||',
        ')',
        '(',
        'class:',
        '!',
        '"unterminated',
      ]) {
        expect(() => FilterExpression.parse(input), returnsNormally);
      }
    });
  });

  group('chips', () {
    test('empty input has no chips and is isEmpty', () {
      final expr = FilterExpression.parse('');
      expect(expr.chips, isEmpty);
      expect(expr.isEmpty, isTrue);
      expect(expr.matches(_t('anything')), isTrue);
    });

    test('chips are ordered left-to-right with correct labels', () {
      final expr = FilterExpression.parse('library:app class:Foo');
      expect(expr.chips, hasLength(2));
      expect(expr.chips[0].leafId, 0);
      expect(expr.chips[0].label, 'library:app');
      expect(expr.chips[1].leafId, 1);
      expect(expr.chips[1].label, 'class:Foo');
    });

    test('negated leaf label includes a leading !', () {
      final expr = FilterExpression.parse('!class:Foo');
      expect(expr.chips.single.label, '!class:Foo');
    });

    test('a NOT wrapping a compound does not mark its leaves negated', () {
      final expr = FilterExpression.parse('!(class:A || class:B)');
      expect(expr.chips, hasLength(2));
      expect(expr.chips.every((c) => !c.negated), isTrue);
    });
  });

  group('removeLeaf', () {
    test('prunes one side of && and keeps the other', () {
      final expr = FilterExpression.parse('class:A && class:B');
      final next = expr.removeLeaf(0);

      expect(next.chips, hasLength(1));
      // Leaf ids are stable, not renumbered after removal.
      expect(next.chips.single.leafId, 1);
      expect(next.chips.single.value, 'B');
      expect(next.matches(_t('B')), isTrue);
      expect(next.matches(_t('A')), isFalse);

      final reparsed = FilterExpression.parse(next.text);
      expect(reparsed.chips, hasLength(1));
      expect(reparsed.matches(_t('B')), isTrue);
      expect(reparsed.matches(_t('A')), isFalse);
    });

    test('prunes one side of || and keeps the other', () {
      final expr = FilterExpression.parse('class:A || class:B');
      final next = expr.removeLeaf(1);

      expect(next.chips, hasLength(1));
      expect(next.matches(_t('A')), isTrue);
      expect(next.matches(_t('B')), isFalse);
    });

    test('folds ! around a compound into the remaining leaf', () {
      final expr = FilterExpression.parse('!(class:A || class:B)');
      final next = expr.removeLeaf(0);

      expect(next.text, '!class:B');
      expect(next.chips, hasLength(1));
      expect(next.chips.single.negated, isTrue);
      expect(next.chips.single.value, 'B');
      expect(next.matches(_t('B')), isFalse);
      expect(next.matches(_t('C')), isTrue);
    });

    test('removing the only leaf yields an empty, matches-all filter', () {
      final expr = FilterExpression.parse('class:Solo');
      final next = expr.removeLeaf(0);

      expect(next.isEmpty, isTrue);
      expect(next.text, '');
      expect(next.error, isNull);
      expect(next.matches(_t('anything')), isTrue);
    });
  });

  group('FilterBar widget', () {
    testWidgets('renders a chip per leaf and removes one on tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _Harness(initial: FilterExpression.parse('class:Alpha class:Bravo')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(RadarFilterChip), findsNWidgets(2));
      // Exact match: the search field also contains "class:Alpha" as a
      // substring of its full raw text, so textContaining would be
      // ambiguous. The chip label includes the trailing remove glyph.
      expect(find.text('class:Alpha ×'), findsOneWidget);
      expect(find.text('class:Bravo ×'), findsOneWidget);

      await tester.tap(find.byType(RadarFilterChip).first);
      await tester.pumpAndSettle();

      expect(find.byType(RadarFilterChip), findsNWidgets(1));
    });
  });
}

// ── Widget smoke test ────────────────────────────────────────────────────

class _Harness extends StatefulWidget {
  const _Harness({required this.initial});

  final FilterExpression initial;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late FilterExpression _expression = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Theme(
        data: radarDarkTheme(),
        child: Scaffold(
          body: FilterBar(
            expression: _expression,
            onChanged: (next) => setState(() => _expression = next),
          ),
        ),
      ),
    );
  }
}
