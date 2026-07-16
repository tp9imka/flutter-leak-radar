import 'package:vm_service/vm_service.dart';

/// A [VmService] whose un-overridden members throw, so each test declares
/// only the RPCs it actually exercises.
///
/// Pure-Dart stand-in for flutter_test's `Fake`, which is unavailable here.
class FakeVmService implements VmService {
  @override
  Object? noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} is not stubbed on this fake',
  );
}
