import 'package:radar_native/radar_native.dart';
import 'package:test/test.dart';

void main() {
  group('FfiAllocationSite', () {
    const site = FfiAllocationSite(
      site: 'Foo.bar',
      file: 'foo.dart:1',
      stillLiveBytes: 100,
      stillLiveBlocks: 2,
      dartStack: ['Foo.bar  foo.dart:1', 'main  main.dart:10'],
    );

    test('value equality', () {
      const other = FfiAllocationSite(
        site: 'Foo.bar',
        file: 'foo.dart:1',
        stillLiveBytes: 100,
        stillLiveBlocks: 2,
        dartStack: ['Foo.bar  foo.dart:1', 'main  main.dart:10'],
      );

      expect(site, other);
      expect(site.hashCode, other.hashCode);
    });

    test('differs when dartStack differs', () {
      const other = FfiAllocationSite(
        site: 'Foo.bar',
        file: 'foo.dart:1',
        stillLiveBytes: 100,
        stillLiveBlocks: 2,
        dartStack: ['Foo.bar  foo.dart:1'],
      );

      expect(site, isNot(other));
    });

    test('JSON round-trips', () {
      final back = FfiAllocationSite.fromJson(site.toJson());
      expect(back, site);
    });
  });

  group('FfiAllocationLog', () {
    test('totalStillLiveBytes sums sites', () {
      final log = FfiAllocationLog(
        capturedAt: DateTime.utc(2026, 7, 3, 12),
        sites: const [
          FfiAllocationSite(
            site: 'A',
            file: 'a.dart:1',
            stillLiveBytes: 300,
            stillLiveBlocks: 2,
            dartStack: [],
          ),
          FfiAllocationSite(
            site: 'B',
            file: 'b.dart:2',
            stillLiveBytes: 50,
            stillLiveBlocks: 1,
            dartStack: [],
          ),
        ],
      );

      expect(log.totalStillLiveBytes, 350);
    });

    test('toJson carries a version envelope', () {
      final log = FfiAllocationLog(
        capturedAt: DateTime.utc(2026, 7, 3),
        sites: const [],
      );

      expect(log.toJson()['version'], 1);
    });

    test('fromJson(toJson()) round-trips capturedAt + sites', () {
      final log = FfiAllocationLog(
        capturedAt: DateTime.utc(2026, 7, 3, 9, 30),
        sites: const [
          FfiAllocationSite(
            site: 'A',
            file: 'a.dart:1',
            stillLiveBytes: 300,
            stillLiveBlocks: 2,
            dartStack: ['A  a.dart:1'],
          ),
        ],
      );

      final back = FfiAllocationLog.fromJson(log.toJson());

      expect(back.capturedAt, log.capturedAt);
      expect(back.totalStillLiveBytes, 300);
      expect(back.sites, hasLength(1));
      expect(back.sites.single, log.sites.single);
    });

    test('fromJson tolerates a missing sites list', () {
      final json = <String, Object?>{
        'capturedAt': DateTime.utc(2026, 7, 3).toIso8601String(),
      };

      final log = FfiAllocationLog.fromJson(json);

      expect(log.sites, isEmpty);
      expect(log.totalStillLiveBytes, 0);
    });
  });

  group('JsonFfiAllocationLogParser', () {
    const parser = JsonFfiAllocationLogParser();

    test('groups records sharing a leaf frame into one site', () {
      const source = '''
      {
        "capturedAt": "2026-07-03T12:00:00.000Z",
        "records": [
          {"address": 1, "byteCount": 100,
           "stack": ["A  a.dart:1", "main  main.dart:5"],
           "timestamp": "2026-07-03T11:00:00.000Z"},
          {"address": 2, "byteCount": 200,
           "stack": ["A  a.dart:1", "main  main.dart:5"],
           "timestamp": "2026-07-03T11:00:01.000Z"},
          {"address": 3, "byteCount": 50,
           "stack": ["B  b.dart:2"],
           "timestamp": "2026-07-03T11:00:02.000Z"}
        ]
      }
      ''';

      final log = parser.parse(source);

      expect(log.capturedAt, DateTime.utc(2026, 7, 3, 12));
      expect(log.sites, hasLength(2));

      final siteA = log.sites.firstWhere((s) => s.site == 'A');
      expect(siteA.file, 'a.dart:1');
      expect(siteA.stillLiveBytes, 300);
      expect(siteA.stillLiveBlocks, 2);
      expect(siteA.dartStack, ['A  a.dart:1', 'main  main.dart:5']);

      final siteB = log.sites.firstWhere((s) => s.site == 'B');
      expect(siteB.file, 'b.dart:2');
      expect(siteB.stillLiveBytes, 50);
      expect(siteB.stillLiveBlocks, 1);
      expect(siteB.dartStack, ['B  b.dart:2']);
    });

    test('empty records produce an empty log', () {
      const source =
          '{"capturedAt": "2026-07-03T12:00:00.000Z", "records": []}';

      final log = parser.parse(source);

      expect(log.sites, isEmpty);
      expect(log.totalStillLiveBytes, 0);
    });

    test('a leaf frame with no whitespace separator puts everything in '
        'site and leaves file empty', () {
      const source = '''
      {
        "capturedAt": "2026-07-03T12:00:00.000Z",
        "records": [
          {"address": 1, "byteCount": 10,
           "stack": ["NoSeparatorFrame"],
           "timestamp": "2026-07-03T11:00:00.000Z"}
        ]
      }
      ''';

      final log = parser.parse(source);

      final site = log.sites.single;
      expect(site.site, 'NoSeparatorFrame');
      expect(site.file, '');
    });
  });
}
