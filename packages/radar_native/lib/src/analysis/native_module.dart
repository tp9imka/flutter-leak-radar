import '../model/native_callsite.dart';
import '../model/native_frame.dart';

/// Function names whose leaf frame is an allocator entry point, not a real
/// caller (checked case-insensitively against [NativeFrame.function]).
const Set<String> _allocatorFunctionNames = {
  'malloc',
  'calloc',
  'realloc',
  'free',
  'memalign',
  'aligned_alloc',
  'posix_memalign',
  'operator new',
  'operator new[]',
  'operator delete',
  'operator delete[]',
};

/// The display basename of a mapping path: the segment after the last `/`
/// and, if that still contains a `!` (APK-embedded shared object), the
/// segment after the last `!` too. E.g.
/// `/data/app/../base.apk!libflutter.so` -> `libflutter.so`.
String moduleShortName(String module) {
  final afterSlash = module.split('/').last;
  return afterSlash.split('!').last;
}

/// Whether [frame] is an allocator frame: libc itself, or a known
/// malloc/new-family entry point.
bool _isAllocatorFrame(NativeFrame frame) =>
    moduleShortName(frame.module) == 'libc.so' ||
    _allocatorFunctionNames.contains(frame.function.toLowerCase());

/// The frame a callsite is attributed to: walks [callsite]'s frames
/// leaf-first and skips the leading run of allocator frames (the
/// malloc/calloc/... entry point in libc), returning the first real
/// caller frame. If every frame is an allocator frame, returns the last
/// frame instead. An empty stack attributes to `null`.
NativeFrame? attributedFrame(NativeCallsite callsite) {
  final frames = callsite.frames;
  if (frames.isEmpty) return null;
  for (final frame in frames) {
    if (!_isAllocatorFrame(frame)) return frame;
  }
  return frames.last;
}

/// The module a callsite is attributed to: [moduleShortName] of
/// [attributedFrame]'s module, or `''` for an empty stack.
String attributedModule(NativeCallsite callsite) =>
    moduleShortName(attributedFrame(callsite)?.module ?? '');
