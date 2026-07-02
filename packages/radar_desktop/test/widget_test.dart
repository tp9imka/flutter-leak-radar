import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/main.dart';
import 'package:radar_desktop/src/shell/desktop_rail.dart';

void main() {
  testWidgets('app boots into the desktop shell', (tester) async {
    await tester.pumpWidget(const RadarDesktopApp());
    expect(find.byType(DesktopRail), findsOneWidget);
  });
}
