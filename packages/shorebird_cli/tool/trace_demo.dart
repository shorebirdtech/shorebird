// Demo: build a realistic trace file and run shorebird_cli's
// BuildTraceSummary against it to show what shipping trace telemetry
// looks like end-to-end. Run from the shorebird_cli package:
//
//   dart run tool/trace_demo.dart

import 'dart:convert';
import 'dart:io';

import 'package:shorebird_build_trace/shorebird_build_trace.dart';
import 'package:shorebird_cli/src/artifact_builder/build_environment.dart';
import 'package:shorebird_cli/src/artifact_builder/build_trace_summary.dart';

Duration ms(int n) => Duration(milliseconds: n);

void main() {
  final out = File('/tmp/demo-trace.json');
  final tracer = BuildTracer();

  final flutterPid = 12345;
  final gradlePid = 12346;
  final assemblePid = 12347;

  tracer
    ..addProcessNameMetadata(pid: flutterPid, name: 'flutter_tool')
    ..addThreadNameMetadata(pid: flutterPid, tid: 1, name: 'flutter tool')
    ..addThreadNameMetadata(pid: flutterPid, tid: 2, name: 'gradle (wait)')
    ..addThreadNameMetadata(pid: flutterPid, tid: 5, name: 'network')
    ..addProcessNameMetadata(pid: gradlePid, name: 'gradle')
    ..addThreadNameMetadata(pid: gradlePid, tid: 1, name: 'gradle tasks')
    ..addProcessNameMetadata(pid: assemblePid, name: 'flutter assemble')
    ..addThreadNameMetadata(
      pid: assemblePid,
      tid: 1,
      name: 'flutter assemble',
    );

  final t0 = DateTime.fromMillisecondsSinceEpoch(1700000000000);

  tracer.addCompleteEvent(
    name: 'pre-gradle setup',
    cat: TraceCategory.flutter.wireName,
    pid: flutterPid,
    tid: 1,
    start: t0,
    end: t0.add(ms(1500)),
  );

  tracer.recordNetworkSpan(
    method: 'GET',
    host: 'storage.googleapis.com',
    pid: flutterPid,
    tid: 5,
    start: t0.add(ms(200)),
    end: t0.add(ms(1100)),
    status: 200,
    contentLength: 45000000,
  );

  final gradleStart = t0.add(ms(1500));
  final gradleEnd = gradleStart.add(ms(85000));
  tracer.addCompleteEvent(
    name: 'gradle bundleRelease',
    cat: TraceCategory.gradle.wireName,
    pid: flutterPid,
    tid: 2,
    start: gradleStart,
    end: gradleEnd,
  );

  final tasks = <(String, GradleTaskKind, int)>[
    (':app:compileFlutterBuildRelease', GradleTaskKind.flutterGradlePlugin, 8000),
    (':app:packLibsflutterBuildRelease', GradleTaskKind.flutterGradlePlugin, 2000),
    (':app:compileReleaseKotlin', GradleTaskKind.kotlinCompile, 12000),
    (':app:compileReleaseJavaWithJavac', GradleTaskKind.javaCompile, 5000),
    (':app:javaPreCompileRelease', GradleTaskKind.javaCompile, 800),
    (':camera_android:compileReleaseKotlin', GradleTaskKind.kotlinCompile, 3000),
    (':path_provider_android:compileReleaseKotlin', GradleTaskKind.kotlinCompile, 1000),
    (':url_launcher_android:compileReleaseKotlin', GradleTaskKind.kotlinCompile, 900),
    (':app:mergeExtDexRelease', GradleTaskKind.dex, 4000),
    (':app:mergeDexRelease', GradleTaskKind.dex, 2000),
    (':app:dexBuilderRelease', GradleTaskKind.dex, 6000),
    (':app:mergeReleaseResources', GradleTaskKind.resources, 2000),
    (':app:processReleaseResources', GradleTaskKind.resources, 3000),
    (':app:mergeReleaseManifest', GradleTaskKind.resources, 400),
    (':app:minifyReleaseWithR8', GradleTaskKind.r8Minify, 18000),
    (':app:lintVitalRelease', GradleTaskKind.lint, 5000),
    (':app:lintAnalyzeRelease', GradleTaskKind.lint, 7000),
    (':app:transformClassesWithDexBuilderForRelease', GradleTaskKind.transform, 3000),
    (':app:bundleReleaseClassesToCompileJar', GradleTaskKind.bundle, 1000),
    (':app:bundleReleaseResources', GradleTaskKind.bundle, 600),
    (':app:packageRelease', GradleTaskKind.packaging, 4000),
    (':app:createMd5Release', GradleTaskKind.packaging, 200),
    (':app:prepareLintJarForPublish', GradleTaskKind.gradleScaffold, 150),
    (':app:generateReleaseAarMetadata', GradleTaskKind.gradleScaffold, 90),
    (':app:checkReleaseAarMetadata', GradleTaskKind.gradleScaffold, 120),
    (':app:copyReleaseJniLibsProjectOnly', GradleTaskKind.gradleScaffold, 80),
    (':app:validateSigningRelease', GradleTaskKind.gradleScaffold, 40),
  ];
  var gradleCursor = gradleStart.add(ms(2000));
  for (final (path, kind, durMs) in tasks) {
    tracer.addCompleteEvent(
      name: path,
      cat: TraceCategory.gradleTask.wireName,
      pid: gradlePid,
      tid: 1,
      start: gradleCursor,
      end: gradleCursor.add(ms(durMs)),
      args: {
        'kind': kind.wireName,
        'skipped': false,
        'upToDate': false,
        'fromCache': false,
      },
    );
    gradleCursor = gradleCursor.add(ms(durMs));
  }
  for (final cached in [
    ':app:generateReleaseBuildConfig',
    ':app:mergeReleaseJavaResource',
  ]) {
    tracer.addCompleteEvent(
      name: cached,
      cat: TraceCategory.gradleTask.wireName,
      pid: gradlePid,
      tid: 1,
      start: gradleCursor,
      end: gradleCursor.add(ms(50)),
      args: {
        'kind': GradleTaskKind.gradleScaffold.wireName,
        'skipped': false,
        'upToDate': false,
        'fromCache': true,
      },
    );
    gradleCursor = gradleCursor.add(ms(50));
  }

  var assembleCursor = gradleStart.add(ms(25000));
  final assembleTargets = <(String, int)>[
    ('kernel_snapshot', 9000),
    ('android_aot_release_arm64', 22000),
    ('android_aot_release_armv7', 19000),
    ('android_aot_release_x64', 12000),
    ('copy_assets', 2000),
    ('gen_localizations', 400),
  ];
  for (final (name, durMs) in assembleTargets) {
    tracer.addCompleteEvent(
      name: name,
      cat: TraceCategory.assemble.wireName,
      pid: assemblePid,
      tid: 1,
      start: assembleCursor,
      end: assembleCursor.add(ms(durMs)),
      args: {'target': name, 'skipped': false, 'succeeded': true},
    );
    assembleCursor = assembleCursor.add(ms(durMs));
  }

  tracer
    ..addCompleteEvent(
      name: 'post-gradle processing',
      cat: TraceCategory.flutter.wireName,
      pid: flutterPid,
      tid: 1,
      start: gradleEnd,
      end: gradleEnd.add(ms(500)),
    )
    ..addCompleteEvent(
      name: 'flutter build appbundle',
      cat: TraceCategory.flutter.wireName,
      pid: flutterPid,
      tid: 1,
      start: t0,
      end: gradleEnd.add(ms(500)),
    );

  tracer.writeToFile(out);
  print('Wrote trace: ${out.path} (${out.lengthSync()} bytes)\n');

  final summary = BuildTraceSummary.tryFromFile(
    out,
    platform: 'android',
    shorebirdOverhead: const Duration(milliseconds: 2300),
    environment: BuildEnvironment(
      isCi: true,
      ciProvider: 'github',
      gradleBuildCacheEnabled: true,
      gradleConfigurationCacheEnabled: false,
      gradleParallelEnabled: true,
      gradleDaemonEnabled: true,
      gradleDevelocityDetected: false,
      gradleInitScriptCount: 0,
      iosCcacheAvailable: false,
    ),
  );

  print('=== build-trace-android-summary.json ===');
  print(const JsonEncoder.withIndent('  ').convert(summary?.toJson()));
}
