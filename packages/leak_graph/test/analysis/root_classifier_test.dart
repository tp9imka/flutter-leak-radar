import 'package:leak_graph/leak_graph.dart';
import 'package:test/test.dart';

void main() {
  group('classifyRoot', () {
    test('_Timer → timer', () {
      expect(classifyRoot(['_Timer', 'HomeState']), RootKind.timer);
    });

    test('Timer → timer', () {
      expect(classifyRoot(['Timer', 'HomeState']), RootKind.timer);
    });

    test('*StreamSubscription → stream', () {
      expect(
        classifyRoot(['_BufferingStreamSubscription', 'AppCubit']),
        RootKind.stream,
      );
    });

    test('*StreamController → stream', () {
      expect(
        classifyRoot(['_SyncStreamController', 'MyBloc']),
        RootKind.stream,
      );
    });

    test('Finalizer → finalizer', () {
      expect(classifyRoot(['Finalizer', 'Obj']), RootKind.finalizer);
    });

    test('NativeFinalizer → finalizer', () {
      expect(classifyRoot(['NativeFinalizer', 'Obj']), RootKind.finalizer);
    });

    test('*FinalizerEntry → finalizer', () {
      expect(classifyRoot(['_FinalizerEntry', 'Obj']), RootKind.finalizer);
    });

    test('_Closure → closure', () {
      expect(classifyRoot(['_Closure', 'Captured']), RootKind.closure);
    });

    test('Context → closure', () {
      expect(classifyRoot(['Context', 'Captured']), RootKind.closure);
    });

    test('_Context → closure', () {
      expect(classifyRoot(['_Context', 'Captured']), RootKind.closure);
    });

    test('Closure → closure', () {
      expect(classifyRoot(['Closure', 'Captured']), RootKind.closure);
    });

    test('Library root → staticOrGlobal', () {
      expect(
        classifyRoot(['Library', 'AppRegistry', 'Foo']),
        RootKind.staticOrGlobal,
      );
    });

    test('Class root → staticOrGlobal', () {
      expect(classifyRoot(['Class', 'Foo']), RootKind.staticOrGlobal);
    });

    test('Type root → staticOrGlobal', () {
      expect(classifyRoot(['Type', 'Foo']), RootKind.staticOrGlobal);
    });

    test('_Type root → staticOrGlobal', () {
      expect(classifyRoot(['_Type', 'Foo']), RootKind.staticOrGlobal);
    });

    test('PatchClass root → staticOrGlobal', () {
      expect(classifyRoot(['PatchClass', 'Foo']), RootKind.staticOrGlobal);
    });

    test('plain class → other', () {
      expect(classifyRoot(['SomeWidget', 'SomeState']), RootKind.other);
    });

    test('empty path → other', () {
      expect(classifyRoot([]), RootKind.other);
    });

    test('timer takes priority over staticOrGlobal at root', () {
      expect(classifyRoot(['_Timer', 'Library', 'Foo']), RootKind.timer);
    });
  });
}
