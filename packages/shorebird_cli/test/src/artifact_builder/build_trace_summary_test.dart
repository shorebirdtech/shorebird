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
      expect(s.flutterAssemble.targetCount, 0);
      expect(s.shorebirdOverheadMs, isNull);
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
      expect(s.flutterBuildMs, 3005);
      expect(s.shorebirdOverheadMs, 500);
      expect(s.totalMs, 3505);

      // Network
      expect(s.network.ms, 300);
      expect(s.network.callCount, 1);

      // Dart
      expect(s.dart.totalMs, 700);
      expect(s.dart.kernelSnapshotMs, 500);
      expect(s.dart.genSnapshotMs, 200);
      expect(s.dart.buildMs, 100);
      expect(s.dartMs, 700);

      // Native (outer 3000ms − sum of assemble 800ms = 2200ms)
      expect(s.native.buildMs, 3000);
      expect(s.native.compileMs, 2200);

      // Flutter tool
      expect(s.flutterToolMs, 2);

      // Android-specific
      expect(s.android, isNotNull);
      final g = s.android!.gradle;
      expect(g.taskCount, 4);
      // Kotlin sum: 1+2+5 = 8s
      expect(g.kotlinCompileMs, 8000);
      expect(g.r8MinifyMs, 20000);
      expect(g.taskMaxMs, 20000);
      // Sorted us: [1M, 2M, 5M, 20M]; floor(4*0.5)=2 → 5M; floor(4*0.9)=3 → 20M
      expect(g.taskP50Ms, 5000);
      expect(g.taskP90Ms, 20000);

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
        // xcode phases on tid=4 cat=xcode_phase
        _event(
          name: 'CompileC',
          cat: 'xcode_phase',
          ts: 0,
          dur: 30_000_000,
          tid: 4,
        ),
        _event(
          name: 'SwiftCompile',
          cat: 'xcode_phase',
          ts: 0,
          dur: 25_000_000,
          tid: 4,
        ),
        _event(name: 'Ld', cat: 'xcode_phase', ts: 0, dur: 5_000_000, tid: 4),
        _event(
          name: 'CodeSign',
          cat: 'xcode_phase',
          ts: 0,
          dur: 2_000_000,
          tid: 4,
        ),
        _event(
          name: 'CopyPlistFile',
          cat: 'xcode_phase',
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
      expect(s.ios!.podInstall.ms, 60000);
      expect(s.ios!.podInstall.analyzeMs, 5000);
      expect(s.ios!.podInstall.downloadMs, 30000);
      expect(s.ios!.podInstall.generateMs, 20000);
      expect(s.ios!.podInstall.integrateMs, 5000);
      expect(s.ios!.xcode.phaseCount, 5);
      expect(s.ios!.xcode.compileCMs, 30000);
      expect(s.ios!.xcode.swiftCompileMs, 25000);
      expect(s.ios!.xcode.ldMs, 5000);
      expect(s.ios!.xcode.codeSignMs, 2000);
      expect(s.ios!.xcode.otherPhasesMs, 1000);
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
      expect(j['version'], 5);
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
        expect(s!.flutterBuildMs, 1500);
        expect(s.dart.kernelSnapshotMs, 1000);
        expect(s.dartMs, 1000);
      });
    });
  });
}
