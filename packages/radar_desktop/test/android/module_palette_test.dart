import 'package:flutter_test/flutter_test.dart';
import 'package:radar_desktop/src/android/module_palette.dart';
import 'package:radar_native/radar_native.dart';
import 'package:radar_ui/radar_ui.dart';

void main() {
  test('moduleKindColor maps every kind to its palette token', () {
    expect(
      moduleKindColor(NativeModuleKind.app),
      OriginTokens.color(RadarOrigin.project),
    );
    expect(moduleKindColor(NativeModuleKind.gpuDriver), RadarColors.warning);
    expect(moduleKindColor(NativeModuleKind.engine), RadarColors.text50);
    expect(
      moduleKindColor(NativeModuleKind.plugin),
      OriginTokens.color(RadarOrigin.dependency),
    );
    expect(
      moduleKindColor(NativeModuleKind.system),
      OriginTokens.color(RadarOrigin.framework),
    );
    expect(moduleKindColor(NativeModuleKind.unknown), RadarColors.text25);
  });

  test('app agrees with OriginTokens project hue (one ownership palette)', () {
    expect(
      moduleKindColor(NativeModuleKind.app),
      OriginTokens.color(RadarOrigin.project),
    );
    expect(moduleKindColor(NativeModuleKind.app), isNot(RadarColors.accent));
  });

  test('plugin is no longer accent (was inverted vs. app=info)', () {
    expect(moduleKindColor(NativeModuleKind.plugin), isNot(RadarColors.accent));
  });

  test('moduleKindLabel maps every kind to its display label', () {
    expect(moduleKindLabel(NativeModuleKind.app), 'App');
    expect(moduleKindLabel(NativeModuleKind.gpuDriver), 'GPU driver');
    expect(moduleKindLabel(NativeModuleKind.engine), 'Engine');
    expect(moduleKindLabel(NativeModuleKind.plugin), 'Plugin');
    expect(moduleKindLabel(NativeModuleKind.system), 'Runtime');
    expect(moduleKindLabel(NativeModuleKind.unknown), '—');
  });
}
