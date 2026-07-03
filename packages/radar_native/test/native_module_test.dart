import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

NativeCallsite cs(List<List<String>> frames) => NativeCallsite(
  frames: [for (final f in frames) NativeFrame(function: f[0], module: f[1])],
  allocBytes: 0,
  allocCount: 0,
  freeBytes: 0,
  freeCount: 0,
);

void main() {
  test('moduleShortName strips path and apk! prefix', () {
    expect(
      moduleShortName('/apex/com.android.runtime/lib64/bionic/libc.so'),
      'libc.so',
    );
    expect(
      moduleShortName(
        '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so',
      ),
      'libflutter.so',
    );
    expect(
      moduleShortName('/data/app/~~H==/com.katim.leak_lab-H==/base.apk'),
      'base.apk',
    );
    expect(moduleShortName(''), '');
  });
  test('attributedModule skips the malloc/libc allocator leaf', () {
    final c = cs([
      ['calloc', '/apex/com.android.runtime/lib64/bionic/libc.so'],
      ['', '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so'],
      ['', '/data/app/~~H==/com.katim.leak_lab-H==/base.apk'],
    ]);
    expect(attributedModule(c), 'libflutter.so');
  });
  test('attributedModule on empty frames -> empty string', () {
    expect(attributedModule(cs(const [])), '');
  });
  test(
    'attributedModule when all frames are allocators -> last module short',
    () {
      final c = cs([
        ['malloc', '/apex/.../bionic/libc.so'],
        ['free', '/system/lib64/libc.so'],
      ]);
      expect(attributedModule(c), 'libc.so');
    },
  );
  test(
    'attributedFrame returns the first non-allocator frame (full module)',
    () {
      final c = cs([
        ['calloc', '/apex/com.android.runtime/lib64/bionic/libc.so'],
        [
          'flutter::Foo',
          '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so',
        ],
      ]);
      final f = attributedFrame(c)!;
      expect(
        f.module,
        '/data/app/~~H==/com.katim.connect-H==/base.apk!libflutter.so',
      ); // FULL path
      expect(f.function, 'flutter::Foo');
    },
  );
  test('attributedFrame on empty frames is null', () {
    expect(attributedFrame(cs(const [])), isNull);
  });
}
