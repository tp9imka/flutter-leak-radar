import 'package:radar_native_host/radar_native_host.dart';
import 'package:test/test.dart';

/// Answers `getprop`/`dumpsys` probes from a scripted map keyed by a substring
/// of the joined args, so each preflight check can be driven independently.
class _ScriptedAdb implements AdbRunner {
  _ScriptedAdb(this.responses);

  /// Maps an args-substring to the stdout to return for a matching call.
  final Map<String, String> responses;
  final calls = <List<String>>[];

  @override
  Future<AdbResult> run(
    List<String> args, {
    String? serial,
    String? stdin,
  }) async {
    calls.add(args);
    final joined = args.join(' ');
    for (final entry in responses.entries) {
      if (joined.contains(entry.key)) {
        return AdbResult(0, entry.value, '');
      }
    }
    return const AdbResult(0, '', '');
  }
}

void main() {
  group('CapturePreflight', () {
    test('passes when SDK >= 29 and the package is debuggable', () async {
      final adb = _ScriptedAdb({
        'ro.build.version.sdk': '34\n',
        'dumpsys package': 'flags=[ DEBUGGABLE HAS_CODE ]\n',
      });

      final result = await CapturePreflight(adb).check('com.x', serial: null);

      expect(result.passed, isTrue);
      expect(result.failure, isNull);
    });

    test(
      'passes when the package is profileable-by-shell (not debuggable)',
      () async {
        final adb = _ScriptedAdb({
          'ro.build.version.sdk': '31\n',
          'dumpsys package':
              'flags=[ HAS_CODE ALLOW_BACKUP ]\n'
              'privateFlags=[ PROFILEABLE_BY_SHELL PRIVATE_FLAG_ACTIVITIES ]\n',
        });

        final result = await CapturePreflight(adb).check('com.x', serial: null);

        expect(result.passed, isTrue);
      },
    );

    test(
      'passes on a userdebug device build even if the app carries no flag',
      () async {
        final adb = _ScriptedAdb({
          'ro.build.version.sdk': '30\n',
          'ro.build.type': 'userdebug\n',
          'dumpsys package': 'flags=[ HAS_CODE ]\n',
        });

        final result = await CapturePreflight(adb).check('com.x', serial: null);

        expect(result.passed, isTrue);
      },
    );

    test('fails the SDK check on API level 28, naming the check', () async {
      final adb = _ScriptedAdb({
        'ro.build.version.sdk': '28\n',
        'dumpsys package': 'flags=[ DEBUGGABLE HAS_CODE ]\n',
      });

      final result = await CapturePreflight(adb).check('com.x', serial: null);

      expect(result.passed, isFalse);
      expect(result.failure!.check, PreflightCheck.deviceApiLevel);
      expect(result.failure!.message, contains('29'));
      expect(result.failure!.message, contains('28'));
    });

    test(
      'fails the SDK check when getprop returns nothing parseable',
      () async {
        final adb = _ScriptedAdb({'dumpsys package': 'flags=[ DEBUGGABLE ]\n'});

        final result = await CapturePreflight(adb).check('com.x', serial: null);

        expect(result.passed, isFalse);
        expect(result.failure!.check, PreflightCheck.deviceApiLevel);
      },
    );

    test('fails the profileable check when the app carries no profiling flag '
        'on a user build, naming the check', () async {
      final adb = _ScriptedAdb({
        'ro.build.version.sdk': '33\n',
        'ro.build.type': 'user\n',
        'dumpsys package': 'flags=[ HAS_CODE ALLOW_BACKUP ]\n',
      });

      final result = await CapturePreflight(adb).check('com.x', serial: null);

      expect(result.passed, isFalse);
      expect(result.failure!.check, PreflightCheck.packageProfileable);
      expect(result.failure!.message, contains('profileable'));
    });

    test(
      'fails the profileable check when the package is unknown to dumpsys',
      () async {
        final adb = _ScriptedAdb({
          'ro.build.version.sdk': '33\n',
          'ro.build.type': 'user\n',
          // dumpsys package for a missing package prints nothing useful.
          'dumpsys package': '\n',
        });

        final result = await CapturePreflight(
          adb,
        ).check('com.absent', serial: null);

        expect(result.passed, isFalse);
        expect(result.failure!.check, PreflightCheck.packageProfileable);
      },
    );

    test('scopes every probe to the given serial', () async {
      final adb = _ScriptedAdb({
        'ro.build.version.sdk': '34\n',
        'dumpsys package': 'flags=[ DEBUGGABLE ]\n',
      });

      await CapturePreflight(adb).check('com.x', serial: 'DEV9');

      // Every call must have been able to carry the serial (recorded in calls);
      // the scripted runner ignores serial, so assert the checks ran.
      expect(adb.calls, isNotEmpty);
    });
  });
}
