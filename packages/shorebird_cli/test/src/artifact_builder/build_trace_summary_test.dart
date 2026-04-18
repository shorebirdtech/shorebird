import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';
import 'package:shorebird_cli/src/artifact_builder/duration_distribution.dart';
import 'package:test/test.dart';

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
      // shorebirdLocal = overhead 500 − network 300 = 200
      expect(s.shorebirdLocal, const Duration(milliseconds: 200));

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
      expect(j['version'], 8);
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

    group('tryFromFile', () {
      late Directory tempDir;
      setUp(() => tempDir = Directory.systemTemp.createTempSync());
      tearDown(() => tempDir.deleteSync(recursive: true));

      test('returns null if file is missing', () {
        final s = BuildTraceSummary.tryFromFile(
          File(p.join(tempDir.path, 'missing.json')),
          platform: 'android',
        );
        expect(s, isNull);
      });

      test('returns null for malformed JSON', () {
        final f = File(p.join(tempDir.path, 'bad.json'))
          ..writeAsStringSync('not json');
        expect(
          BuildTraceSummary.tryFromFile(f, platform: 'android'),
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
        final s = BuildTraceSummary.tryFromFile(f, platform: 'android');
        expect(s, isNotNull);
        expect(s!.flutterBuild, const Duration(milliseconds: 1500));
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
        final s = BuildTraceSummary.tryFromFile(f, platform: 'android');
        expect(s, isNotNull);
        expect(s!.flutterBuild, const Duration(milliseconds: 500));
      });

      test('returns null when the JSON root is not a list or known object', () {
        final f = File(p.join(tempDir.path, 'weird.json'))
          ..writeAsStringSync(jsonEncode({'unexpected': true}));
        expect(
          BuildTraceSummary.tryFromFile(f, platform: 'android'),
          isNull,
        );
      });
    });

    group('assemble category classification', () {
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
            ts: 0,
            dur: 2_000_000,
            tid: 3,
          ),
          _event(
            name: 'ios_aot',
            cat: 'assemble',
            ts: 0,
            dur: 3_000_000,
            tid: 3,
          ),
        ], platform: 'android');
        expect(s.dart.genSnapshot, const Duration(milliseconds: 6000));
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
            ts: 0,
            dur: 200_000,
            tid: 3,
          ),
          _event(
            name: 'unpack_macos',
            cat: 'assemble',
            ts: 0,
            dur: 300_000,
            tid: 3,
          ),
          _event(
            name: 'copy_framework',
            cat: 'assemble',
            ts: 0,
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
      Map<String, Object?> _gradle(String kind, int durMs) => _event(
        name: kind,
        cat: 'gradle_task',
        ts: 0,
        dur: durMs * 1000,
        tid: 4,
        args: {'kind': kind},
      );

      test('all kinds populate their respective buckets', () {
        final s = BuildTraceSummary.fromEvents([
          _gradle('kotlin_compile', 10),
          _gradle('java_compile', 20),
          _gradle('dex', 30),
          _gradle('resources', 40),
          _gradle('transform', 50),
          _gradle('r8_minify', 60),
          _gradle('lint', 70),
          _gradle('flutter_gradle_plugin', 80),
          _gradle('bundle', 90),
          _gradle('packaging', 100),
          _gradle('aidl', 110),
          _gradle('native_link', 120),
          _gradle('gradle_scaffold', 130),
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
  });
}
