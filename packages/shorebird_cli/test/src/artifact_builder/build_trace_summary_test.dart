import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';
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
      expect(s.flutterBuildMs, 0);
      expect(s.dartMs, 0);
      expect(s.nonDartMs, 0);
      expect(s.assembleTargetCount, 0);
      expect(s.shorebirdOverheadMs, isNull);
    });

    test('categorizes tids and target names (android)', () {
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
          name: 'android_aot_bundle_release_android-arm64',
          cat: 'assemble',
          ts: 703_000,
          dur: 40_000,
          tid: 3,
        ),
        _event(
          name: 'aot_android_asset_bundle',
          cat: 'assemble',
          ts: 743_000,
          dur: 20_000,
          tid: 3,
        ),
        _event(
          name: 'gen_dart_plugin_registrant',
          cat: 'assemble',
          ts: 763_000,
          dur: 1000,
          tid: 3,
          args: {'skipped': true},
        ),
        _event(
          name: 'dart_build',
          cat: 'assemble',
          ts: 764_000,
          dur: 100_000,
          tid: 3,
        ),
        _event(
          name: '_composite',
          cat: 'assemble',
          ts: 864_000,
          dur: 10_000,
          tid: 3,
        ),
        _event(
          name: 'flutter build apk',
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
      expect(s.flutterBuildMs, 3005);
      expect(s.kernelSnapshotMs, 500);
      // 200ms android_aot + 40ms android_aot_bundle = 240ms
      expect(s.genSnapshotMs, 240);
      // aot_android_asset_bundle now goes to genSnapshot
      // (contains 'aot_bundle'), so assets is just the rest.
      expect(s.dartBuildMs, 100);
      expect(s.codegenMs, 1);
      expect(s.otherAssembleMs, 10);
      expect(s.dartMs, 740);
      expect(s.nonDartMs, 3005 - 740);
      expect(s.nativeBuildMs, 3000);
      expect(s.flutterToolMs, 2);
      expect(s.assembleTargetCount, 7);
      expect(s.skippedAssembleTargetCount, 1);
      expect(s.shorebirdOverheadMs, 500);
      expect(s.totalMs, 3505);
    });

    test('sums per-gradle-task and network buckets', () {
      final events = [
        // gradle outer span
        _event(
          name: 'gradle assembleRelease',
          cat: 'gradle',
          ts: 0,
          dur: 100_000_000,
          tid: 2,
        ),
        // per-task events on tid=4 (from init script)
        for (final dur in const [1_000_000, 2_000_000, 5_000_000, 500_000])
          _event(
            name: ':some_plugin:compileReleaseKotlin',
            cat: 'gradle_task',
            ts: 0,
            dur: dur,
            tid: 4,
            args: {'kind': 'kotlin_compile', 'owner': 'some_plugin'},
          ),
        _event(
          name: ':app:dexBuilderRelease',
          cat: 'gradle_task',
          ts: 0,
          dur: 3_000_000,
          tid: 4,
          args: {'kind': 'dex', 'owner': 'app'},
        ),
        _event(
          name: ':app:mergeReleaseResources',
          cat: 'gradle_task',
          ts: 0,
          dur: 700_000,
          tid: 4,
          args: {'kind': 'resources', 'owner': 'app'},
        ),
        // network events on any tid, category=network
        _event(
          name: 'GET api.shorebird.dev',
          cat: 'network',
          ts: 0,
          dur: 120_000,
          tid: 5,
        ),
        _event(
          name: 'GET download.shorebird.dev',
          cat: 'network',
          ts: 0,
          dur: 3_500_000,
          tid: 5,
        ),
        _event(
          name: 'flutter build apk',
          cat: 'flutter',
          ts: 0,
          dur: 100_000_000,
          tid: 1,
        ),
      ];
      final s = BuildTraceSummary.fromEvents(events, platform: 'android');
      expect(s.networkMs, 3620); // 120 + 3500
      expect(s.networkCallCount, 2);
      // kotlin durations: 1+2+5+0.5 = 8.5s
      expect(s.kotlinCompileMs, 8500);
      expect(s.dexMs, 3000);
      expect(s.resourcesMs, 700);
      expect(s.gradleTaskCount, 6);
      // Sum: 1+2+5+0.5+3+0.7 = 12.2s
      expect(s.gradleTaskSumMs, 12200);
      expect(s.gradleTaskMaxMs, 5000);
      // Sorted us: [500k, 700k, 1M, 2M, 3M, 5M]
      // index floor(6*0.5)=3 → 2M, index floor(6*0.9)=5 → 5M
      expect(s.gradleTaskP50Ms, 2000);
      expect(s.gradleTaskP90Ms, 5000);
    });

    test('categorizes iOS-specific target names', () {
      final events = [
        _event(
          name: 'xcode archive',
          cat: 'xcode',
          ts: 0,
          dur: 50_000_000,
          tid: 2,
        ),
        _event(
          name: 'kernel_snapshot_program',
          cat: 'assemble',
          ts: 0,
          dur: 9_000_000,
          tid: 3,
        ),
        _event(
          name: 'ios_aot',
          cat: 'assemble',
          ts: 9_000_000,
          dur: 5_000_000,
          tid: 3,
        ),
        _event(
          name: 'dart_build',
          cat: 'assemble',
          ts: 14_000_000,
          dur: 10_000_000,
          tid: 3,
        ),
        _event(
          name: 'release_unpack_ios',
          cat: 'assemble',
          ts: 24_000_000,
          dur: 1_500_000,
          tid: 3,
        ),
        _event(
          name: 'release_ios_bundle_flutter_assets',
          cat: 'assemble',
          ts: 25_500_000,
          dur: 700_000,
          tid: 3,
        ),
        _event(
          name: 'flutter build ios',
          cat: 'flutter',
          ts: 0,
          dur: 50_000_000,
          tid: 1,
        ),
      ];
      final s = BuildTraceSummary.fromEvents(events, platform: 'ios');
      expect(s.kernelSnapshotMs, 9000);
      expect(s.genSnapshotMs, 5000);
      expect(s.dartBuildMs, 10000);
      expect(s.assetsMs, 2200); // release_unpack_ios + bundle_flutter_assets
      expect(s.dartMs, 14000);
      // nativeCompileMs = nativeBuildMs - all assemble sums
      // = 50000 - (9000+5000+10000+2200) = 23800
      expect(s.nativeCompileMs, 23800);
    });

    test('toJson has the v4 fields, no identifiers', () {
      final s = BuildTraceSummary(
        platform: 'ios',
        flutterBuildMs: 10,
        flutterToolMs: 1,
        nativeBuildMs: 9,
        kernelSnapshotMs: 2,
        genSnapshotMs: 3,
        dartBuildMs: 0,
        assetsMs: 1,
        codegenMs: 1,
        otherAssembleMs: 0,
        assembleTargetCount: 5,
        skippedAssembleTargetCount: 1,
        shorebirdOverheadMs: 4,
        networkMs: 2,
        networkCallCount: 3,
      );
      final json = s.toJson();
      expect(json, {
        'version': 4,
        'platform': 'ios',
        'totalMs': 14,
        'flutterBuildMs': 10,
        'shorebirdOverheadMs': 4,
        'networkMs': 2,
        'networkCallCount': 3,
        'dartMs': 5,
        'nonDartMs': 5,
        'nativeCompileMs': 2, // 9 - (2+3+0+1+1+0) = 2
        'kernelSnapshotMs': 2,
        'genSnapshotMs': 3,
        'dartBuildMs': 0,
        'assetsMs': 1,
        'codegenMs': 1,
        'otherAssembleMs': 0,
        'flutterToolMs': 1,
        'nativeBuildMs': 9,
        'assembleTargetCount': 5,
        'skippedAssembleTargetCount': 1,
        'gradleTaskCount': 0,
        'gradleTaskSumMs': 0,
        'gradleTaskP50Ms': 0,
        'gradleTaskP90Ms': 0,
        'gradleTaskMaxMs': 0,
        'kotlinCompileMs': 0,
        'javaCompileMs': 0,
        'dexMs': 0,
        'resourcesMs': 0,
        'transformMs': 0,
        'r8MinifyMs': 0,
        'lintMs': 0,
        'flutterGradlePluginMs': 0,
        'bundleMs': 0,
        'packagingMs': 0,
        'aidlMs': 0,
        'nativeLinkMs': 0,
        'gradleScaffoldMs': 0,
      });
      expect(
        json.keys.any(
          (k) =>
              k.toLowerCase().contains('path') ||
              k.toLowerCase().contains('file') ||
              k.toLowerCase().contains('user') ||
              k.toLowerCase().contains('name'),
        ),
        isFalse,
      );
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
        expect(s!.flutterBuildMs, 1500);
        expect(s.kernelSnapshotMs, 1000);
        expect(s.dartMs, 1000);
      });
    });

    test('negative shorebird overhead treated as zero by caller (clamped)', () {
      final s = BuildTraceSummary.fromEvents(
        [
          _event(
            name: 'flutter build apk',
            cat: 'flutter',
            ts: 0,
            dur: 10_000,
            tid: 1,
          ),
        ],
        platform: 'android',
        shorebirdOverhead: Duration.zero,
      );
      expect(s.shorebirdOverheadMs, 0);
      expect(s.totalMs, s.flutterBuildMs);
    });
  });
}
