import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leak_graph/leak_graph.dart';
import 'package:radar_ui/radar_ui.dart';
import 'package:radar_workbench/radar_workbench.dart';

Widget _wrap(Widget child, Size size) => MaterialApp(
  home: Theme(
    data: radarDarkTheme(),
    child: Scaffold(
      body: SizedBox.fromSize(size: size, child: child),
    ),
  ),
);

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

ClassCountDiff _diff(String name) => ClassCountDiff(
  before: ClassCount(
    className: name,
    libraryUri: Uri.parse('package:my_app/p.dart'),
    instanceCount: 0,
    shallowBytes: 0,
  ),
  after: ClassCount(
    className: name,
    libraryUri: Uri.parse('package:my_app/p.dart'),
    instanceCount: 1,
    shallowBytes: 500,
  ),
);

Widget _table({Map<String, TriageDisplay> triage = const {}}) => DiffTable(
  diffs: [_diff('LeakyThing')],
  summary: const SizedBox.shrink(),
  selected: null,
  onSelected: (_) {},
  triage: triage,
);

void main() {
  testWidgets('renders no chip by default (empty triage)', (tester) async {
    _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(_wrap(_table(), const Size(1280, 800)));
    await tester.pump();
    expect(find.byType(TriageChip), findsNothing);
  });

  testWidgets('renders a supplied chip for a matching class', (tester) async {
    _setSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      _wrap(
        _table(triage: const {'LeakyThing': TriageDisplay.known}),
        const Size(1280, 800),
      ),
    );
    await tester.pump();
    expect(find.text('KNOWN'), findsOneWidget);
  });

  for (final width in const [722.0, 800.0, 1280.0]) {
    testWidgets('a diff row with a chip does not overflow at $width', (
      tester,
    ) async {
      final size = Size(width, 600);
      _setSize(tester, size);
      await tester.pumpWidget(
        _wrap(
          _table(triage: const {'LeakyThing': TriageDisplay.acknowledged}),
          size,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
