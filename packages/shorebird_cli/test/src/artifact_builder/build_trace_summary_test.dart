import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';
import 'package:shorebird_cli/src/artifact_builder/duration_distribution.dart';
import 'package:test/test.dart';
import '../helpers.dart';

Map<String, Object?> _event({
  required String name,
  required String cat,
  required int ts,
  required int dur,
  required int tid,
  Map<String, Object?>? args,
}) => {
  'ph': 'X',
  'name': name,
  'cat': cat,
  'ts': ts,
  'dur': dur,
  'pid': 1,
  'tid': tid,
  'args': ?args,
};

void main() {
  useTempWorkingDirectory();
  group(BuildTraceSummary, () {
    test('empty events → zero summary', () {
      final s = BuildTraceSummary.fromEvents([], platform: 'android');
      expect(s.flutterBuild, Duration.zero);
      expect(s.dart.total, Duration.zero);
      expect(s.flutterAssemble.targetCount, 0);
      expect(s.shorebirdOverhead, isNull);
      // Platform is android → android populated, ios null.
      expect(s.android, isNotNull);
      expect(s.ios, isNull);
    });

    group('flutter process span', () {
      // Flutter's umbrella starts after its pub get and artifact
      // downloads; the process span shorebird_cli records starts at spawn.
      final events = [
        _event(
          name: 'flutter process',
          cat: 'subprocess',
          ts: 0,
          dur: 10_000_000,
          tid: 2,
          args: {'command': 'ios'},
        ),
        _event(
          name: 'flutter build ios',
          cat: 'flutter',
          ts: 4_000_000,
          dur: 5_000_000,
          tid: 1,
        ),
        // A download during flutter_tools' startup is Flutter's, not
        // Shorebird's.
        _event(
          name: 'GET artifact',
          cat: 'network',
          ts: 1_000_000,
          dur: 2_000_000,
          tid: 1,
        ),
        _event(
          name: 'POST patch',
          cat: 'network',
          ts: 11_000_000,
          dur: 1_000_000,
          tid: 1,
        ),
      ];

      test('is the Flutter build, startup included', () {
        final s = BuildTraceSummary.fromEvents(
          events,
          platform: 'ios',
          shorebirdOverhead: const Duration(seconds: 3),
        );
        expect(s.flutterBuild, const Duration(seconds: 10));
        expect(s.total, const Duration(seconds: 13));
        expect(s.network.shorebird, const Duration(seconds: 1));
        // Not double counted as flutter-tool time.
        expect(s.flutterTool, Duration.zero);
      });

      test('sums one span per flutter build', () {
        final s = BuildTraceSummary.fromEvents([
          ...events,
          _event(
            name: 'flutter process',
            cat: 'subprocess',
            ts: 20_000_000,
            dur: 6_000_000,
            tid: 2,
            args: {'command': 'apk'},
          ),
        ], platform: 'android');
        expect(s.flutterBuild, const Duration(seconds: 16));
      });

      test('falls back to the umbrella without one', () {
        final s = BuildTraceSummary.fromEvents(
          events.where((e) => e['name'] != 'flutter process').toList(),
          platform: 'ios',
        );
        expect(s.flutterBuild, const Duration(seconds: 5));
        // The startup download is outside the umbrella, so Shorebird's.
        expect(s.network.shorebird, const Duration(seconds: 3));
      });
    });

    test('unknown cat is dropped — does not contribute to any bucket', () {
      // A future producer emits a category this consumer doesn't know yet.
      // Forward-compat contract: parse to TraceCategory.unknown and skip.
      final events = [
        _event(
          name: 'mystery-event',
          cat: 'brand-new-future-category',
          ts: 0,
          dur: 9_999_999,
          tid: 1,
        ),
      ];
      final s = BuildTraceSummary.fromEvents(events, platform: 'android');
      expect(s.flutterBuild, Duration.zero);
      expect(s.native.build, Duration.zero);
      expect(s.network.duration, Duration.zero);
      expect(s.flutterAssemble.targetCount, 0);
    });

    test('android trace → nested gradle + android stats', () {
      final events = [
        _event(
          name: 'pre-gradle setup',
          cat: 'flutter',
          ts: 0,
          dur: 2000,
          tid: 1,
        ),
        _event(
          name: 'gradle assembleRelease',
          cat: 'gradle',
          ts: 2000,
          dur: 3_000_000,
          tid: 2,
        ),
        _event(
          name: 'kernel_snapshot_program',
          cat: 'assemble',
          ts: 3000,
          dur: 500_000,
          tid: 3,
        ),
        _event(
          name: 'android_aot',
          cat: 'assemble',
          ts: 503_000,
          dur: 200_000,
          tid: 3,
        ),
        _event(
          name: 'dart_build',
          cat: 'assemble',
          ts: 703_000,
          dur: 100_000,
          tid: 3,
        ),
        // per-task events (tid=4, cat=gradle_task)
        for (final dur in const [1_000_000, 2_000_000, 5_000_000])
          _event(
            name: ':some_plugin:compileReleaseKotlin',
            cat: 'gradle_task',
            ts: 0,
            dur: dur,
            tid: 4,
            args: {'kind': 'kotlin_compile'},
          ),
        _event(
          name: ':app:minifyReleaseWithR8',
          cat: 'gradle_task',
          ts: 0,
          dur: 20_000_000,
          tid: 4,
          args: {'kind': 'r8_minify'},
        ),
        _event(
          name: 'POST api.shorebird.dev',
          cat: 'network',
          ts: 0,
          dur: 300_000,
          tid: 5,
        ),
        _event(
          name: 'flutter build appbundle',
          cat: 'flutter',
          ts: 0,
          dur: 3_005_000,
          tid: 1,
        ),
      ];

      final s = BuildTraceSummary.fromEvents(
        events,
        platform: 'android',
        shorebirdOverhead: const Duration(milliseconds: 500),
      );

      // Top level
      expect(s.flutterBuild, const Duration(milliseconds: 3005));
      expect(s.shorebirdOverhead, const Duration(milliseconds: 500));
      expect(s.total, const Duration(milliseconds: 3505));
      // The POST lies inside the flutter build span, so none of it is
      // Shorebird's network time: shorebirdLocal is all of overhead.
      expect(s.shorebirdLocal, const Duration(milliseconds: 500));

      // Network
      expect(s.network.duration, const Duration(milliseconds: 300));
      expect(s.network.callCount, 1);

      // Dart
      expect(s.dart.total, const Duration(milliseconds: 700));
      expect(s.dart.kernelSnapshot, const Duration(milliseconds: 500));
      expect(s.dart.genSnapshot, const Duration(milliseconds: 200));
      expect(s.dart.build, const Duration(milliseconds: 100));

      // Native (outer 3000ms − sum of assemble 800ms = 2200ms)
      expect(s.native.build, const Duration(milliseconds: 3000));
      expect(s.native.compile, const Duration(milliseconds: 2200));

      // Flutter tool
      expect(s.flutterTool, const Duration(milliseconds: 2));

      // Android-specific
      expect(s.android, isNotNull);
      final g = s.android!.gradle;
      expect(g.taskDistribution.count, 4);
      // Kotlin sum: 1+2+5 = 8s
      expect(g.kotlinCompile, const Duration(milliseconds: 8000));
      expect(g.r8Minify, const Duration(milliseconds: 20000));
      expect(g.taskDistribution.max, const Duration(milliseconds: 20000));
      // Sorted us: [1M, 2M, 5M, 20M]; floor(4*0.5)=2 → 5M; floor(4*0.9)=3 → 20M
      expect(g.taskDistribution.p50, const Duration(milliseconds: 5000));
      expect(g.taskDistribution.p90, const Duration(milliseconds: 20000));

      expect(s.ios, isNull);
    });

    test('ios trace → nested podInstall + xcode stats', () {
      final events = [
        _event(
          name: 'pod install',
          cat: 'subprocess',
          ts: 0,
          dur: 60_000_000,
          tid: 1,
        ),
        _event(
          name: 'pod install: analyzing',
          cat: 'subprocess',
          ts: 0,
          dur: 5_000_000,
          tid: 1,
        ),
        _event(
          name: 'pod install: downloading',
          cat: 'subprocess',
          ts: 5_000_000,
          dur: 30_000_000,
          tid: 1,
        ),
        _event(
          name: 'pod install: generating',
          cat: 'subprocess',
          ts: 35_000_000,
          dur: 20_000_000,
          tid: 1,
        ),
        _event(
          name: 'pod install: integrating',
          cat: 'subprocess',
          ts: 55_000_000,
          dur: 5_000_000,
          tid: 1,
        ),
        _event(
          name: 'xcode archive',
          cat: 'xcode',
          ts: 0,
          dur: 100_000_000,
          tid: 2,
        ),
        // xcode subsections on tid=4 cat=xcode_subsection
        _event(
          name: 'Build target A',
          cat: 'xcode_subsection',
          ts: 0,
          dur: 30_000_000,
          tid: 4,
        ),
        _event(
          name: 'Build target B',
          cat: 'xcode_subsection',
          ts: 0,
          dur: 25_000_000,
          tid: 4,
        ),
        _event(
          name: 'Build target C',
          cat: 'xcode_subsection',
          ts: 0,
          dur: 5_000_000,
          tid: 4,
        ),
        _event(
          name: 'Build target D',
          cat: 'xcode_subsection',
          ts: 0,
          dur: 2_000_000,
          tid: 4,
        ),
        _event(
          name: 'Build target E',
          cat: 'xcode_subsection',
          ts: 0,
          dur: 1_000_000,
          tid: 4,
        ),
        _event(
          name: 'flutter build ios',
          cat: 'flutter',
          ts: 0,
          dur: 200_000_000,
          tid: 1,
        ),
      ];
      final s = BuildTraceSummary.fromEvents(events, platform: 'ios');

      expect(s.ios, isNotNull);
      expect(s.android, isNull);
      expect(s.ios!.podInstall.duration, const Duration(milliseconds: 60000));
      expect(s.ios!.podInstall.analyze, const Duration(milliseconds: 5000));
      expect(s.ios!.podInstall.download, const Duration(milliseconds: 30000));
      expect(s.ios!.podInstall.generate, const Duration(milliseconds: 20000));
      expect(s.ios!.podInstall.integrate, const Duration(milliseconds: 5000));
      expect(s.ios!.xcode.subsectionDistribution.count, 5);
      // Sum: 30+25+5+2+1 = 63s
      expect(
        s.ios!.xcode.subsectionDistribution.sum,
        const Duration(milliseconds: 63000),
      );
      expect(
        s.ios!.xcode.subsectionDistribution.max,
        const Duration(milliseconds: 30000),
      );
      // Sorted us: [1M, 2M, 5M, 25M, 30M]
      // floor(5*0.5)=2 → 5M; floor(5*0.9)=4 → 30M
      expect(
        s.ios!.xcode.subsectionDistribution.p50,
        const Duration(milliseconds: 5000),
      );
      expect(
        s.ios!.xcode.subsectionDistribution.p90,
        const Duration(milliseconds: 30000),
      );
    });

    test('macos trace → xcode stats populated under the ios key', () {
      final events = [
        _event(
          name: 'pod install',
          cat: 'subprocess',
          ts: 0,
          dur: 4_000_000,
          tid: 1,
        ),
        _event(
          name: 'Build target Runner',
          cat: 'xcode_subsection',
          ts: 5_000_000,
          dur: 20_000_000,
          tid: 1,
        ),
        _event(
          name: 'xcode build',
          cat: 'xcode',
          ts: 4_000_000,
          dur: 30_000_000,
          tid: 2,
        ),
        _event(
          name: 'flutter build macos',
          cat: 'flutter',
          ts: 0,
          dur: 40_000_000,
          tid: 1,
        ),
      ];
      final s = BuildTraceSummary.fromEvents(events, platform: 'macos');

      expect(s.platform, 'macos');
      expect(s.android, isNull);
      expect(s.ios, isNotNull);
      expect(s.ios!.podInstall.duration, const Duration(seconds: 4));
      expect(s.ios!.xcode.subsectionDistribution.count, 1);
      expect(s.native.build, const Duration(seconds: 30));
      expect(s.toJson()['ios'], isNotNull);
    });

    test('linux trace → no platform-specific stats', () {
      final s = BuildTraceSummary.fromEvents([], platform: 'linux');
      expect(s.android, isNull);
      expect(s.ios, isNull);
    });

    group('native.compile', () {
      // gen_snapshot inside gradle: [10s, 13s) within [5s, 35s).
      final nested = _event(
        name: 'aot_android_asset_bundle',
        cat: 'assemble',
        ts: 10_000_000,
        dur: 3_000_000,
        tid: 1,
      );
      final gradle = _event(
        name: 'gradle bundleRelease',
        cat: 'gradle',
        ts: 5_000_000,
        dur: 30_000_000,
        tid: 2,
      );

      test('subtracts assemble time that ran inside the native build', () {
        final s = BuildTraceSummary.fromEvents([
          nested,
          gradle,
        ], platform: 'android');
        expect(s.native.build, const Duration(seconds: 30));
        expect(s.native.compile, const Duration(seconds: 27));
      });

      test('does not subtract assemble time that ran beside it', () {
        // ios-framework builds App.framework in-process ([0s, 8s)), then
        // runs xcodebuild for plugins ([10s, 20s)). None of the assemble
        // work is inside xcodebuild, so native compile is the full span.
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'kernel_snapshot',
            cat: 'assemble',
            ts: 0,
            dur: 8_000_000,
            tid: 3,
          ),
          _event(
            name: 'xcode build plugins (iphoneos)',
            cat: 'xcode',
            ts: 10_000_000,
            dur: 10_000_000,
            tid: 2,
          ),
        ], platform: 'ios');
        expect(s.native.build, const Duration(seconds: 10));
        expect(s.native.compile, const Duration(seconds: 10));
      });

      test('subtracts only the overlapping portion', () {
        // assemble [0s, 8s) straddles the start of xcode [6s, 16s).
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'kernel_snapshot',
            cat: 'assemble',
            ts: 0,
            dur: 8_000_000,
            tid: 3,
          ),
          _event(
            name: 'xcode build',
            cat: 'xcode',
            ts: 6_000_000,
            dur: 10_000_000,
            tid: 2,
          ),
        ], platform: 'ios');
        expect(s.native.compile, const Duration(seconds: 8));
      });

      test('treats an assemble event without ts as nested', () {
        // Older producers emitted no timestamps; they all nested
        // assemble inside the native build, so keep subtracting.
        final s = BuildTraceSummary.fromEvents([
          {
            'ph': 'X',
            'name': 'kernel_snapshot',
            'cat': 'assemble',
            'dur': 3_000_000,
            'pid': 1,
            'tid': 1,
          },
          gradle,
        ], platform: 'android');
        expect(s.native.compile, const Duration(seconds: 27));
      });

      test('clamps at zero', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'kernel_snapshot',
            cat: 'assemble',
            ts: 5_000_000,
            dur: 30_000_000,
            tid: 1,
          ),
          _event(
            name: 'kernel_snapshot',
            cat: 'assemble',
            ts: 5_000_000,
            dur: 30_000_000,
            tid: 1,
          ),
          gradle,
        ], platform: 'android');
        expect(s.native.compile, Duration.zero);
      });
    });

    test('toJson shape is nested and omits the other platform', () {
      final events = [
        _event(
          name: 'flutter build appbundle',
          cat: 'flutter',
          ts: 0,
          dur: 10_000_000,
          tid: 1,
        ),
      ];
      final s = BuildTraceSummary.fromEvents(events, platform: 'android');
      final j = s.toJson();
      expect(j['version'], 12);
      expect(j['platform'], 'android');
      expect(j['android'], isA<Map<String, Object?>>());
      expect(j.containsKey('ios'), isFalse);
      final android = j['android']! as Map<String, Object?>;
      expect(android['gradle'], isA<Map<String, Object?>>());
      // No path/name/user identifiers at any level.
      final flat = jsonEncode(j).toLowerCase();
      expect(flat.contains('"path"'), isFalse);
      expect(flat.contains('"file"'), isFalse);
      expect(flat.contains('"user"'), isFalse);
    });

    group('setup phases', () {
      List<Map<String, Object?>> setupEvents() => [
        _event(
          name: 'setup: flutter_install',
          cat: 'setup',
          ts: 0,
          dur: 90_000_000,
          tid: 2,
        ),
        _event(
          name: 'setup: flutter_precache',
          cat: 'setup',
          ts: 90_000_000,
          dur: 240_000_000,
          tid: 2,
        ),
        // Emitted once per `updateAll` call; the later ones no-op.
        _event(
          name: 'setup: shorebird_cache',
          cat: 'setup',
          ts: 330_000_000,
          dur: 30_000_000,
          tid: 2,
        ),
        _event(
          name: 'setup: shorebird_cache',
          cat: 'setup',
          ts: 360_000_000,
          dur: 1_000_000,
          tid: 2,
        ),
      ];

      test('bucket by phase and add back-to-back repeats', () {
        final s = BuildTraceSummary.fromEvents(
          setupEvents(),
          platform: 'android',
        );
        expect(s.setup.flutterInstall, const Duration(seconds: 90));
        expect(s.setup.flutterPrecache, const Duration(seconds: 240));
        expect(s.setup.shorebirdCache, const Duration(seconds: 31));
        expect(s.setup.total, const Duration(seconds: 361));
      });

      test('are a subset of overhead, not of flutterBuild', () {
        // The case this exists for: a cold CI runner where setup
        // dominates and Flutter's own build is comparatively quick.
        final s = BuildTraceSummary.fromEvents(
          [
            ...setupEvents(),
            _event(
              name: 'flutter build appbundle',
              cat: 'flutter',
              ts: 361_000_000,
              dur: 60_000_000,
              tid: 1,
            ),
          ],
          platform: 'android',
          shorebirdOverhead: const Duration(seconds: 380),
        );
        expect(s.flutterBuild, const Duration(seconds: 60));
        expect(s.setup.total, lessThan(s.shorebirdOverhead!));
        // Without the setup breakdown this whole 361s reads as local work.
        expect(s.shorebirdLocal, const Duration(seconds: 380));
      });

      test('unknown phase does not land in a named bucket', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'setup: from_the_future',
            cat: 'setup',
            ts: 0,
            dur: 5_000_000,
            tid: 2,
          ),
        ], platform: 'android');
        expect(s.setup.total, Duration.zero);
      });

      test('toJson serializes all fields', () {
        final s = BuildTraceSummary.fromEvents(
          setupEvents(),
          platform: 'android',
        );
        expect(s.toJson()['setup'], {
          'totalMs': 361_000,
          'flutterInstallMs': 90_000,
          'flutterPrecacheMs': 240_000,
          'shorebirdCacheMs': 31_000,
          'downloads': {
            'count': 0,
            'cacheHitCount': 0,
            'failedCount': 0,
            'retryCount': 0,
            'bytes': 0,
            'ms': 0,
            'redirectMs': 0,
            'ttfb': DurationDistribution.empty().toJson(),
            'hosts': <String, Object?>{},
            'edges': <String, Object?>{},
          },
          'cold': true,
        });
      });

      test('cold when Flutter was installed or its precache ran', () {
        // A checkout from an interrupted earlier run: precache only.
        final precacheOnly = BuildTraceSummary.fromEvents(
          setupEvents()
              .where((e) => e['name'] != 'setup: flutter_install')
              .toList(),
          platform: 'android',
        );
        expect(precacheOnly.setup.cold, isTrue);
      });

      test('warm when only the shorebird cache was refreshed', () {
        final s = BuildTraceSummary.fromEvents(
          setupEvents()
              .where((e) => e['name'] == 'setup: shorebird_cache')
              .toList(),
          platform: 'android',
        );
        expect(s.setup.cold, isFalse);
        expect(s.toJson()['setup'], containsPair('cold', false));
      });
    });

    group('precache downloads', () {
      Map<String, Object?> download({
        required int ts,
        required int dur,
        required Map<String, Object?> args,
      }) => _event(
        name: 'download ${args['host']}',
        cat: 'download',
        ts: ts,
        dur: dur,
        tid: 1,
        args: args,
      );

      test('totals fetches by host and edge', () {
        final s = BuildTraceSummary.fromEvents([
          // Two concurrent fetches redirected to GCS, one retried.
          download(
            ts: 0,
            dur: 4_000_000,
            args: {
              'host': 'download.shorebird.dev',
              'servedBy': 'storage.googleapis.com',
              'status': 200,
              'bytes': 1000,
              'redirectUs': 300_000,
              'ttfbUs': 500_000,
              'retries': 1,
              'edge': 'cloudflare:BOM',
            },
          ),
          download(
            ts: 1_000_000,
            dur: 5_000_000,
            args: {
              'host': 'download.shorebird.dev',
              'servedBy': 'storage.googleapis.com',
              'status': 200,
              'bytes': 2000,
              'redirectUs': 200_000,
              'ttfbUs': 700_000,
              'retries': 0,
              'edge': 'cloudflare:BOM',
            },
          ),
          download(
            ts: 10_000_000,
            dur: 1_000_000,
            args: {
              'host': 'maven.example.com',
              'status': 404,
              'bytes': 0,
              'ttfbUs': 900_000,
              'retries': 0,
            },
          ),
          download(
            ts: 12_000_000,
            dur: 0,
            args: {'host': 'download.shorebird.dev', 'cacheHit': true},
          ),
        ], platform: 'android');
        final downloads = s.setup.downloads;
        expect(downloads.count, 3);
        expect(downloads.cacheHitCount, 1);
        expect(downloads.failedCount, 1);
        expect(downloads.retryCount, 1);
        expect(downloads.bytes, 3000);
        expect(downloads.duration, const Duration(seconds: 7));
        expect(downloads.redirect, const Duration(milliseconds: 500));
        expect(
          downloads.timeToFirstByte.p50,
          const Duration(milliseconds: 700),
        );
        expect(downloads.toJson()['hosts'], {
          'storage.googleapis.com': {'count': 2, 'bytes': 3000, 'ms': 6000},
          'maven.example.com': {'count': 1, 'bytes': 0, 'ms': 1000},
        });
        expect(downloads.edges, {'cloudflare:BOM': 2});
      });

      test('reports names that are not plain hostnames as other', () {
        final s = BuildTraceSummary.fromEvents([
          download(
            ts: 0,
            dur: 1000,
            args: {
              'host': 'https://user:secret@example.com/x',
              'status': 200,
              'edge': 'cloudflare BOM; extra',
            },
          ),
        ], platform: 'android');
        expect(s.setup.downloads.hosts.keys, ['other']);
        expect(s.setup.downloads.edges, {'other': 1});
      });

      test('caps distinct hosts and edges', () {
        final s = BuildTraceSummary.fromEvents([
          for (var i = 0; i < 20; i++)
            download(
              ts: i * 1000,
              dur: 1000,
              args: {'host': 'h$i.example.com', 'status': 200, 'edge': 'e:$i'},
            ),
        ], platform: 'android');
        final hosts = s.setup.downloads.hosts;
        expect(hosts, hasLength(17));
        expect(hosts['other']!.count, 4);
        expect(s.setup.downloads.edges['other'], 4);
      });

      test('a fetch fails on an error, not on a missing status', () {
        final s = BuildTraceSummary.fromEvents([
          download(
            ts: 0,
            dur: 1000,
            args: {'host': 'example.com', 'error': 'connection reset'},
          ),
          download(ts: 2000, dur: 1000, args: {'host': 'example.com'}),
        ], platform: 'android');
        expect(s.setup.downloads.count, 2);
        expect(s.setup.downloads.failedCount, 1);
      });

      test('ignores args of the wrong type', () {
        final s = BuildTraceSummary.fromEvents([
          download(
            ts: 0,
            dur: 1000,
            args: {
              'host': 'example.com',
              'status': 200,
              'bytes': '12',
              'retries': '1',
              'redirectUs': null,
              'ttfbUs': 1500.0,
            },
          ),
        ], platform: 'android');
        final downloads = s.setup.downloads;
        expect(downloads.bytes, 0);
        expect(downloads.retryCount, 0);
        expect(downloads.redirect, Duration.zero);
        expect(
          downloads.timeToFirstByte.max,
          const Duration(microseconds: 1500),
        );
      });
    });

    group('tryReadEvents', () {
      late Directory tempDir;
      setUp(() => tempDir = Directory.systemTemp.createTempSync());
      tearDown(() => tempDir.deleteSync(recursive: true));

      test('returns null if file is missing', () {
        expect(
          BuildTraceSummary.tryReadEvents(
            File(p.join(tempDir.path, 'missing.json')),
          ),
          isNull,
        );
      });

      test('returns null for malformed JSON', () {
        final f = File(p.join(tempDir.path, 'bad.json'))
          ..writeAsStringSync('not json');
        expect(
          BuildTraceSummary.tryReadEvents(f),
          isNull,
        );
      });

      test('parses a trace array', () {
        final f = File(p.join(tempDir.path, 'trace.json'))
          ..writeAsStringSync(
            jsonEncode([
              _event(
                name: 'kernel_snapshot_program',
                cat: 'assemble',
                ts: 0,
                dur: 1_000_000,
                tid: 3,
              ),
              _event(
                name: 'flutter build apk',
                cat: 'flutter',
                ts: 0,
                dur: 1_500_000,
                tid: 1,
              ),
            ]),
          );
        final s = BuildTraceSummary.fromEvents(
          BuildTraceSummary.tryReadEvents(f)!,
          platform: 'android',
        );
        expect(s.flutterBuild, const Duration(milliseconds: 1500));
        expect(s.dart.kernelSnapshot, const Duration(milliseconds: 1000));
        expect(s.dart.total, const Duration(milliseconds: 1000));
      });

      test('parses a {"traceEvents": [...]} object shape', () {
        final f = File(p.join(tempDir.path, 'trace.json'))
          ..writeAsStringSync(
            jsonEncode({
              'traceEvents': [
                _event(
                  name: 'flutter build apk',
                  cat: 'flutter',
                  ts: 0,
                  dur: 500_000,
                  tid: 1,
                ),
              ],
            }),
          );
        final s = BuildTraceSummary.fromEvents(
          BuildTraceSummary.tryReadEvents(f)!,
          platform: 'android',
        );
        expect(s.flutterBuild, const Duration(milliseconds: 500));
      });

      test('returns null when the JSON root is not a list or known object', () {
        final f = File(p.join(tempDir.path, 'weird.json'))
          ..writeAsStringSync(jsonEncode({'unexpected': true}));
        expect(
          BuildTraceSummary.tryReadEvents(f),
          isNull,
        );
      });
    });

    group('assemble category classification', () {
      // Back to back: concurrent spans would count once.
      test('aot_assembly / aot_elf / ios_aot → genSnapshot bucket', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'aot_assembly_release',
            cat: 'assemble',
            ts: 0,
            dur: 1_000_000,
            tid: 3,
          ),
          _event(
            name: 'aot_elf_release',
            cat: 'assemble',
            ts: 1_000_000,
            dur: 2_000_000,
            tid: 3,
          ),
          _event(
            name: 'ios_aot',
            cat: 'assemble',
            ts: 3_000_000,
            dur: 3_000_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.dart.genSnapshot, const Duration(milliseconds: 6000));
      });

      test('compile_macos_framework → genSnapshot bucket', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'compile_macos_framework',
            cat: 'assemble',
            ts: 0,
            dur: 4_000_000,
            tid: 3,
          ),
        ], platform: 'macos');
        expect(s.dart.genSnapshot, const Duration(seconds: 4));
        expect(s.flutterAssemble.other, Duration.zero);
      });

      test('dart_build → DartStats.build', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'dart_build',
            cat: 'assemble',
            ts: 0,
            dur: 500_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.dart.build, const Duration(milliseconds: 500));
      });

      test('gen_* → FlutterAssembleStats.codegen', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'gen_localizations',
            cat: 'assemble',
            ts: 0,
            dur: 600_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.flutterAssemble.codegen, const Duration(milliseconds: 600));
      });

      test('various asset-like names → assets bucket', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'bundle_flutter_assets_release',
            cat: 'assemble',
            ts: 0,
            dur: 100_000,
            tid: 3,
          ),
          _event(
            name: 'install_code_assets',
            cat: 'assemble',
            ts: 100_000,
            dur: 200_000,
            tid: 3,
          ),
          _event(
            name: 'unpack_macos',
            cat: 'assemble',
            ts: 300_000,
            dur: 300_000,
            tid: 3,
          ),
          _event(
            name: 'copy_framework',
            cat: 'assemble',
            ts: 600_000,
            dur: 400_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.flutterAssemble.assets, const Duration(milliseconds: 1000));
      });

      test('unknown name → other bucket', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'some_random_target',
            cat: 'assemble',
            ts: 0,
            dur: 700_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.flutterAssemble.other, const Duration(milliseconds: 700));
      });

      test('skipped:true bumps the skippedCount', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'copy_framework',
            cat: 'assemble',
            ts: 0,
            dur: 1000,
            tid: 3,
            args: {'skipped': true},
          ),
        ], platform: 'android');
        expect(s.flutterAssemble.skippedCount, 1);
        expect(s.flutterAssemble.targetCount, 1);
      });
    });

    group('gradle task kinds', () {
      Map<String, Object?> gradle(String kind, int durMs) => _event(
        name: kind,
        cat: 'gradle_task',
        ts: 0,
        dur: durMs * 1000,
        tid: 4,
        args: {'kind': kind},
      );

      test('all kinds populate their respective buckets', () {
        final s = BuildTraceSummary.fromEvents([
          gradle('kotlin_compile', 10),
          gradle('java_compile', 20),
          gradle('dex', 30),
          gradle('resources', 40),
          gradle('transform', 50),
          gradle('r8_minify', 60),
          gradle('lint', 70),
          gradle('flutter_gradle_plugin', 80),
          gradle('bundle', 90),
          gradle('packaging', 100),
          gradle('aidl', 110),
          gradle('native_link', 120),
          gradle('gradle_scaffold', 130),
        ], platform: 'android');

        final g = s.android!.gradle;
        expect(g.kotlinCompile, const Duration(milliseconds: 10));
        expect(g.javaCompile, const Duration(milliseconds: 20));
        expect(g.dex, const Duration(milliseconds: 30));
        expect(g.resources, const Duration(milliseconds: 40));
        expect(g.transform, const Duration(milliseconds: 50));
        expect(g.r8Minify, const Duration(milliseconds: 60));
        expect(g.lint, const Duration(milliseconds: 70));
        expect(g.flutterGradlePlugin, const Duration(milliseconds: 80));
        expect(g.bundle, const Duration(milliseconds: 90));
        expect(g.packaging, const Duration(milliseconds: 100));
        expect(g.aidl, const Duration(milliseconds: 110));
        expect(g.nativeLink, const Duration(milliseconds: 120));
        expect(g.gradleScaffold, const Duration(milliseconds: 130));
      });

      test('cache / up-to-date / executed task counters increment', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'a',
            cat: 'gradle_task',
            ts: 0,
            dur: 1000,
            tid: 4,
            args: {'kind': 'kotlin_compile', 'fromCache': true},
          ),
          _event(
            name: 'b',
            cat: 'gradle_task',
            ts: 0,
            dur: 1000,
            tid: 4,
            args: {'kind': 'kotlin_compile', 'upToDate': true},
          ),
          _event(
            name: 'c',
            cat: 'gradle_task',
            ts: 0,
            dur: 1000,
            tid: 4,
            args: {'kind': 'kotlin_compile'},
          ),
        ], platform: 'android');

        final g = s.android!.gradle;
        expect(g.taskFromCacheCount, 1);
        expect(g.taskUpToDateCount, 1);
        expect(g.taskExecutedCount, 1);
      });
    });

    group('iOS stats', () {
      test('xcode_subsection events populate XcodeStats histogram', () {
        final s = BuildTraceSummary.fromEvents([
          for (final dur in const [100, 200, 300, 1000])
            _event(
              name: 'Build target Foo',
              cat: 'xcode_subsection',
              ts: 0,
              dur: dur * 1000,
              tid: 4,
            ),
        ], platform: 'ios');

        final xcode = s.ios!.xcode;
        expect(xcode.subsectionDistribution.count, 4);
        expect(
          xcode.subsectionDistribution.sum,
          const Duration(milliseconds: 1600),
        );
        expect(
          xcode.subsectionDistribution.max,
          const Duration(milliseconds: 1000),
        );
        expect(
          xcode.subsectionDistribution.p50,
          greaterThanOrEqualTo(const Duration(milliseconds: 100)),
        );
      });

      test('XcodeStats.toJson serializes all fields', () {
        final xcode = XcodeStats(
          subsectionDistribution: DurationDistribution(
            count: 1,
            sum: const Duration(milliseconds: 2),
            p50: const Duration(milliseconds: 3),
            p90: const Duration(milliseconds: 4),
            max: const Duration(milliseconds: 5),
          ),
        );
        expect(xcode.toJson(), {
          'subsectionDistribution': {
            'count': 1,
            'sumMs': 2,
            'p50Ms': 3,
            'p90Ms': 4,
            'maxMs': 5,
          },
        });
      });

      test('PodInstallStats.toJson serializes all fields', () {
        final stats = PodInstallStats(
          duration: const Duration(milliseconds: 1),
          analyze: const Duration(milliseconds: 2),
          download: const Duration(milliseconds: 3),
          generate: const Duration(milliseconds: 4),
          integrate: const Duration(milliseconds: 5),
        );
        expect(stats.toJson(), {
          'ms': 1,
          'analyzeMs': 2,
          'downloadMs': 3,
          'generateMs': 4,
          'integrateMs': 5,
        });
      });

      test('IosStats.toJson nests pod + xcode', () {
        final iosStats = IosStats(
          podInstall: PodInstallStats(
            duration: Duration.zero,
            analyze: Duration.zero,
            download: Duration.zero,
            generate: Duration.zero,
            integrate: Duration.zero,
          ),
          xcode: XcodeStats(
            subsectionDistribution: DurationDistribution.empty(),
          ),
        );
        final json = iosStats.toJson();
        expect(json.keys, containsAll(<String>['podInstall', 'xcode']));
      });
    });

    group('concurrent spans count as wall time', () {
      // One gen_snapshot per Android arch, all started together inside
      // gradle: [10s, 13s), [10s, 14s), [10s, 15s) within [5s, 35s).
      List<Map<String, Object?>> perArch() => [
        for (final (i, secs) in [3, 4, 5].indexed)
          _event(
            name: 'android_aot',
            cat: 'assemble',
            ts: 10_000_000,
            dur: secs * 1_000_000,
            tid: i + 1,
          ),
        _event(
          name: 'gradle bundleRelease',
          cat: 'gradle',
          ts: 5_000_000,
          dur: 30_000_000,
          tid: 9,
        ),
      ];

      test('genSnapshot is the union, not the sum, of per-arch runs', () {
        final s = BuildTraceSummary.fromEvents(perArch(), platform: 'android');
        expect(s.dart.genSnapshot, const Duration(seconds: 5));
        expect(s.dart.total, const Duration(seconds: 5));
      });

      test('dart.total unions kernel and gen_snapshot', () {
        final s = BuildTraceSummary.fromEvents([
          ...perArch(),
          // Overlaps the gen_snapshot runs by 1s.
          _event(
            name: 'kernel_snapshot_program',
            cat: 'assemble',
            ts: 8_000_000,
            dur: 3_000_000,
            tid: 5,
          ),
        ], platform: 'android');
        expect(s.dart.kernelSnapshot, const Duration(seconds: 3));
        expect(s.dart.total, const Duration(seconds: 7));
      });

      test('native.compile subtracts their wall time once', () {
        final s = BuildTraceSummary.fromEvents(perArch(), platform: 'android');
        expect(s.native.compile, const Duration(seconds: 25));
      });

      test('repeated identical events count once', () {
        final s = BuildTraceSummary.fromEvents([
          ...perArch(),
          ...perArch(),
        ], platform: 'android');
        expect(s.dart.genSnapshot, const Duration(seconds: 5));
      });

      test('events without ts are summed, as before timestamps', () {
        final s = BuildTraceSummary.fromEvents([
          for (var i = 0; i < 2; i++)
            {'ph': 'X', 'name': 'android_aot', 'cat': 'assemble', 'dur': 2e6},
        ], platform: 'android');
        expect(s.dart.genSnapshot, const Duration(seconds: 4));
      });

      test('network counts concurrent requests once', () {
        final s = BuildTraceSummary.fromEvents([
          _event(name: 'PUT a', cat: 'network', ts: 0, dur: 2_000_000, tid: 1),
          _event(
            name: 'PUT b',
            cat: 'network',
            ts: 1_000_000,
            dur: 2_000_000,
            tid: 2,
          ),
          _event(
            name: 'GET c',
            cat: 'network',
            ts: 5_000_000,
            dur: 1_000_000,
            tid: 1,
          ),
        ], platform: 'android');
        expect(s.network.duration, const Duration(seconds: 4));
        expect(s.network.callCount, 3);
      });

      test('network.shorebird leaves out setup and the flutter build', () {
        final s = BuildTraceSummary.fromEvents(
          [
            // A shorebird_cache download inside setup [0s, 3s).
            _event(
              name: 'setup: shorebird_cache',
              cat: 'setup',
              ts: 0,
              dur: 3_000_000,
              tid: 1,
            ),
            _event(
              name: 'GET a',
              cat: 'network',
              ts: 0,
              dur: 2_000_000,
              tid: 2,
            ),
            // Straddles the end of setup: 1s inside, 1s outside.
            _event(
              name: 'GET b',
              cat: 'network',
              ts: 2_000_000,
              dur: 2_000_000,
              tid: 2,
            ),
            // A request inside the flutter build [5s, 15s).
            _event(
              name: 'flutter build appbundle',
              cat: 'flutter',
              ts: 5_000_000,
              dur: 10_000_000,
              tid: 3,
            ),
            _event(
              name: 'GET c',
              cat: 'network',
              ts: 6_000_000,
              dur: 1_000_000,
              tid: 4,
            ),
            // Shorebird's upload after the build.
            _event(
              name: 'PUT d',
              cat: 'network',
              ts: 16_000_000,
              dur: 2_000_000,
              tid: 2,
            ),
            // No ts: can't be placed, so it counts.
            {'ph': 'X', 'name': 'GET e', 'cat': 'network', 'dur': 500_000},
          ],
          platform: 'android',
          shorebirdOverhead: const Duration(seconds: 10),
        );
        expect(s.network.duration, const Duration(milliseconds: 7500));
        expect(s.network.shorebird, const Duration(milliseconds: 3500));
        // Overhead less Shorebird's network, not less network.ms (7.5s):
        // setup's downloads stay in setup, Flutter's in the build.
        expect(s.shorebirdLocal, const Duration(milliseconds: 6500));
        expect(
          (s.toJson()['network']! as Map)['shorebirdMs'],
          3500,
        );
      });

      test(
        'shorebirdLocal is zero when Shorebird network exceeds overhead',
        () {
          final s = BuildTraceSummary.fromEvents(
            [
              _event(
                name: 'PUT a',
                cat: 'network',
                ts: 0,
                dur: 2_000_000,
                tid: 2,
              ),
            ],
            platform: 'android',
            shorebirdOverhead: const Duration(seconds: 1),
          );
          expect(s.network.shorebird, const Duration(seconds: 2));
          expect(s.shorebirdLocal, Duration.zero);
        },
      );

      test('network.shorebird subtracts overlapping windows once', () {
        final s = BuildTraceSummary.fromEvents([
          // Setup [0s, 4s) overlaps the first build [2s, 6s); a second
          // build runs [8s, 10s).
          _event(
            name: 'setup: flutter_precache',
            cat: 'setup',
            ts: 0,
            dur: 4_000_000,
            tid: 1,
          ),
          _event(
            name: 'flutter build apk',
            cat: 'flutter',
            ts: 2_000_000,
            dur: 4_000_000,
            tid: 2,
          ),
          _event(
            name: 'flutter build appbundle',
            cat: 'flutter',
            ts: 8_000_000,
            dur: 2_000_000,
            tid: 2,
          ),
          // [1s, 11s) crosses all of them: outside is [6s, 8s) and
          // [10s, 11s).
          _event(
            name: 'GET a',
            cat: 'network',
            ts: 1_000_000,
            dur: 10_000_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.network.duration, const Duration(seconds: 10));
        expect(s.network.shorebird, const Duration(seconds: 3));
      });

      test('setup counts nested cache refreshes once', () {
        final s = BuildTraceSummary.fromEvents([
          _event(
            name: 'setup: shorebird_cache',
            cat: 'setup',
            ts: 0,
            dur: 2_000_000,
            tid: 1,
          ),
          _event(
            name: 'setup: shorebird_cache',
            cat: 'setup',
            ts: 500_000,
            dur: 1_000_000,
            tid: 1,
          ),
          _event(
            name: 'setup: flutter_precache',
            cat: 'setup',
            ts: 1_000_000,
            dur: 3_000_000,
            tid: 2,
          ),
        ], platform: 'android');
        expect(s.setup.shorebirdCache, const Duration(seconds: 2));
        expect(s.setup.flutterPrecache, const Duration(seconds: 3));
        expect(s.setup.total, const Duration(seconds: 4));
      });
    });

    // Real traces from `shorebird release android` on an e2e app.
    // Expected values were computed outside Dart from the same files
    // (union of each bucket's [ts, ts + dur) spans).
    group('real traces', () {
      BuildTraceSummary summarize(String name) => BuildTraceSummary.fromEvents(
        BuildTraceSummary.tryReadEvents(
          File(p.join(fixturesDirectory, 'build_trace', name)),
        )!,
        platform: 'android',
      );

      void expectStagesFitTheirParents(BuildTraceSummary s) {
        expect(s.dart.total, lessThanOrEqualTo(s.flutterBuild));
        expect(
          s.dart.total,
          lessThanOrEqualTo(s.dart.kernelSnapshot + s.dart.genSnapshot),
        );
        expect(
          s.setup.total,
          lessThanOrEqualTo(
            s.setup.flutterInstall +
                s.setup.flutterPrecache +
                s.setup.shorebirdCache,
          ),
        );
        expect(s.native.compile, lessThanOrEqualTo(s.native.build));
        expect(s.network.shorebird, lessThanOrEqualTo(s.network.duration));
      }

      test('a clean release run', () {
        final s = summarize('android_clean.json');
        // Three gen_snapshot runs (arm, arm64, x64) overlap: summed
        // they are 4845 ms.
        expect(s.dart.genSnapshot.inMilliseconds, 2286);
        expect(s.dart.kernelSnapshot.inMilliseconds, 1185);
        expect(s.dart.total.inMilliseconds, 3471);
        expect(s.network.duration.inMilliseconds, 7696);
        expect(s.network.shorebird.inMilliseconds, 7696);
        // Nested shorebird_cache refreshes: summed they are 2493 ms.
        expect(s.setup.total.inMilliseconds, 1948);
        expectStagesFitTheirParents(s);
      });

      test('an accumulated trace counts repeated events once', () {
        // Two commands' worth of events, with the first command's
        // assemble events written twice: what CLIs before summary
        // version 10 left behind.
        final s = summarize('android_accumulated.json');
        // Summed: 13776 ms, as the version 9 summary of this file says.
        expect(s.dart.genSnapshot.inMilliseconds, 4167);
        expect(s.dart.total.inMilliseconds, 6528);
        expect(s.network.duration.inMilliseconds, 14538);
        // 3053 ms of it were shorebird_cache downloads inside setup.
        expect(s.network.shorebird.inMilliseconds, 11485);
        expect(s.setup.total.inMilliseconds, 47839);
        expectStagesFitTheirParents(s);
      });
    });
  });
}
