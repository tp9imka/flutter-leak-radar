import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  test('classifies the real device modules', () {
    expect(
      moduleKind('/vendor/lib64/hw/vulkan.adreno.so'),
      NativeModuleKind.gpuDriver,
    );
    expect(
      moduleKind('/vendor/lib64/egl/libGLESv2_adreno.so'),
      NativeModuleKind.gpuDriver,
    );
    expect(
      moduleKind(
        '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so',
      ),
      NativeModuleKind.engine,
    );
    expect(
      moduleKind('/data/app/~~H==/com.katim.leak_lab-H==/base.apk'),
      NativeModuleKind.app,
    );
    expect(
      moduleKind('/apex/com.android.runtime/lib64/bionic/libc.so'),
      NativeModuleKind.system,
    );
    expect(moduleKind('/system/lib64/libc++.so'), NativeModuleKind.system);
    expect(
      moduleKind('/data/app/~~H==/com.example-H==/base.apk!libwebrtc.so'),
      NativeModuleKind.plugin,
    );
    expect(moduleKind('/[anon:dart-code]'), NativeModuleKind.unknown);
  });
}
