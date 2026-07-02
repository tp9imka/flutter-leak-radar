import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/main.dart';

void main() {
  testWidgets('placeholder app boots', (tester) async {
    await tester.pumpWidget(const RadarDesktopApp());
    expect(find.text('Radar Desktop'), findsOneWidget);
  });
}
