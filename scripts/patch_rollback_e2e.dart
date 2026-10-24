// cspell:words Xvfb
// ignore_for_file: avoid_print

// End-to-end test of rollback: the real CLI against a real server, a real
// Flutter build, and the built app launched, checking which code it runs after
// each patch is published, rolled back or rolled forward. Linux only; the app
// is run headless under Xvfb.
//
// One release, 1.0.0+1, and two patches. Each step changes what the server
// serves, then the app is launched twice (download and apply, then boot) and
// the label it prints says which code it runs:
//
//   patch 1 published          -> patch_1
//   patch 2 published          -> patch_2
//   patch 2 rolled back        -> patch_1  (back to the prior patch)
//   patch 2 rolled forward     -> patch_2
//   patches 2 and 1 rolled back -> release (back to the release)
//
// Prerequisites: Linux with the Flutter Linux build dependencies and Xvfb;
// Shorebird on PATH and signed in (CI signs in with OIDC).
//
// Usage: dart scripts/patch_rollback_e2e.dart [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How long one launch may take to finish its update check, and to print its
/// label.
const updateTimeout = Duration(minutes: 3);
const bootTimeout = Duration(minutes: 1);

const releaseVersion = '1.0.0+1';

final results = <String>[];

/// The app this run made, to delete at the end.
String? runAppId;
final timings = <String>[];
bool failed = false;

/// Why the run stopped before checking every step, if it did.
String? stoppedEarly;

Future<void> main(List<String> args) async {
  final flutter = args.isEmpty ? null : args.single;
  final work = Directory.systemTemp.createTempSync('shorebird_rollback_');
  final xvfb = await Process.start(
    'Xvfb',
    [':99', '-screen', '0', '1024x768x24'],
    mode: ProcessStartMode.inheritStdio,
  );
  Future<void> cleanUp() async {
    report(flutter);
    xvfb.kill();
    final appId = runAppId;
    runAppId = null;
    if (appId != null) {
      // Each run mints an app; delete it so the e2e account's app list stays
      // flat (see patch_e2e.sh).
      print('Deleting e2e app $appId');
      final result = await Process.run('shorebird', [
        'api',
        '-X',
        'DELETE',
        'apps/$appId',
      ]);
      if (result.exitCode != 0) {
        print('⚠️  Failed to delete e2e app $appId: ${result.stderr}');
      }
    }
  }

  // A cancelled or timed-out job is signaled, which skips `finally`.
  final signals = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((_) async {
        stoppedEarly = 'got $signal';
        await cleanUp();
        exit(1);
      }),
  ];
  try {
    await run(work, flutter);
  } catch (error) {
    stoppedEarly = '$error';
    rethrow;
  } finally {
    await cleanUp();
    // Watching a signal keeps the process alive.
    for (final subscription in signals) {
      await subscription.cancel();
    }
  }
  if (failed) {
    print('❌ Results differ from what is expected.');
    exit(1);
  }
  print('✅ All results are as expected.');
}

/// Makes the app, its release and patches, and checks the install after each
/// step.
Future<void> run(Directory work, String? flutter) async {
  await timed(
    'create',
    () => sh(work, pinnedFlutter(), [
      'create',
      'e2e_test',
      '--org',
      'com.example.e2e_test',
      '--empty',
      '--platforms',
      'linux',
    ]),
  );
  final app = Directory('${work.path}/e2e_test');
  // `flutter create` writes the pinned Flutter's SDK constraint and lints,
  // which older Flutter versions can't resolve.
  File('${app.path}/pubspec.yaml').writeAsStringSync('''
name: e2e_test
version: $releaseVersion
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
  File('${app.path}/analysis_options.yaml').deleteSync();
  setLabel(app, 'release');
  await timed('init', () => sh(app, 'shorebird', ['init', '--force', '-v']));
  final hostedUrl =
      Platform.environment['SHOREBIRD_HOSTED_URL'] ??
      'https://api-dev.shorebird.dev';
  final shorebirdYaml = File('${app.path}/shorebird.yaml')
    ..writeAsStringSync('base_url: $hostedUrl\n', mode: FileMode.append);
  runAppId = RegExp(
    r'app_id: (\S+)',
  ).firstMatch(shorebirdYaml.readAsStringSync())!.group(1);

  await timed(
    'release',
    () => sh(app, 'shorebird', [
      'release',
      'linux',
      if (flutter != null) '--flutter-version=$flutter',
      '-v',
    ]),
  );
  // A copy, so later builds don't overwrite it, with its updater state in its
  // own HOME, as on a device.
  final install = Directory('${work.path}/install');
  final copy = Process.runSync('cp', [
    '-r',
    '${app.path}/build/linux/x64/release/bundle',
    install.path,
  ]);
  if (copy.exitCode != 0) throw Exception('cp failed: ${copy.stderr}');
  final home = Directory('${work.path}/install_home')..createSync();

  for (final patch in ['patch_1', 'patch_2']) {
    setLabel(app, patch);
    await timed(
      patch,
      () => sh(app, 'shorebird', [
        'patch',
        'linux',
        '--release-version=$releaseVersion',
        '--allow-asset-diffs',
        '--allow-native-diffs',
        '-v',
      ]),
    );
    await check('$patch published', install, home, expected: patch);
  }

  await setRolledBack(app, 2, rolledBack: true);
  await check('patch 2 rolled back', install, home, expected: 'patch_1');

  await setRolledBack(app, 2, rolledBack: false);
  await check('patch 2 rolled forward', install, home, expected: 'patch_2');

  await setRolledBack(app, 2, rolledBack: true);
  await setRolledBack(app, 1, rolledBack: true);
  await check(
    'patches 2 and 1 rolled back',
    install,
    home,
    expected: 'release',
  );
}

/// Rolls patch [number] back, or forward, with the CLI.
Future<void> setRolledBack(
  Directory app,
  int number, {
  required bool rolledBack,
}) => sh(app, 'shorebird', [
  'patches',
  if (rolledBack) 'rollback' else 'rollforward',
  '--release-version=$releaseVersion',
  '--patch-number=$number',
  '--require-change',
]);

/// Launches the install twice after [step] (once to check for an update and
/// apply what the server says, once to boot) and records whether it runs
/// [expected].
Future<void> check(
  String step,
  Directory install,
  Directory home, {
  required String expected,
}) async {
  final stopwatch = Stopwatch()..start();
  final (updated, updateLog) = await launch(
    install,
    home,
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (!updated) {
    throw Exception(
      "$step: the update check didn't finish (exited, or ran past "
      '$updateTimeout). Its output:\n$updateLog',
    );
  }
  final (booted, bootLog) = await launch(
    install,
    home,
    until: RegExp('rollback-e2e: '),
    timeout: bootTimeout,
  );
  if (!booted) {
    throw Exception(
      '$step: the app printed no label (exited, or ran past $bootTimeout). '
      'Its output:\n$bootLog',
    );
  }
  final running = RegExp(
    'rollback-e2e: ([a-z_0-9]+)',
  ).firstMatch(bootLog)!.group(1);
  final verdict = running == expected ? 'PASS' : 'FAIL';
  if (verdict == 'FAIL') failed = true;
  results.add(
    '| $step | $expected | $running | $verdict '
    '| ${stopwatch.elapsed.inSeconds}s |',
  );
  print('$step: expected $expected, runs $running: $verdict');
  if (verdict == 'FAIL') {
    print('--- update launch log\n$updateLog\n--- boot launch log\n$bootLog');
  }
}

/// Runs the app in [install] until a line of its output matches [until] or
/// [timeout] passes, then stops it. Returns whether a line matched, and its
/// output.
Future<(bool, String)> launch(
  Directory install,
  Directory home, {
  required RegExp until,
  required Duration timeout,
}) async {
  final process = await Process.start(
    '${install.path}/e2e_test',
    [],
    environment: {'HOME': home.path, 'DISPLAY': ':99'},
  );
  final output = StringBuffer();
  final matched = Completer<bool>();
  void onLine(String line) {
    output.writeln(line);
    if (!matched.isCompleted && until.hasMatch(line)) matched.complete(true);
  }

  final streams = [
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine),
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(onLine),
  ];
  unawaited(
    process.exitCode.then(
      (_) => matched.isCompleted ? null : matched.complete(false),
    ),
  );
  final found = await matched.future.timeout(timeout, onTimeout: () => false);
  process.kill();
  await process.exitCode;
  for (final s in streams) {
    await s.cancel();
  }
  return (found, output.toString());
}

/// Runs [executable] in [dir], showing its output; throws if it fails.
Future<void> sh(Directory dir, String executable, List<String> args) async {
  final process = await Process.start(
    executable,
    args,
    workingDirectory: dir.path,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw Exception('$executable ${args.join(' ')} exited with $code.');
  }
}

Future<void> timed(String name, Future<void> Function() body) async {
  final stopwatch = Stopwatch()..start();
  await body();
  timings.add('$name ${stopwatch.elapsed.inSeconds}s');
}

void setLabel(Directory app, String label) {
  File(
    '${app.path}/lib/main.dart',
  ).writeAsStringSync("void main() { print('rollback-e2e: $label'); }\n");
}

/// The Flutter the CLI pins, for `flutter create`; not the version under test.
String pinnedFlutter() {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final revision = File(
    '$root/bin/internal/flutter.version',
  ).readAsStringSync().trim();
  return '$root/bin/cache/flutter/$revision/bin/flutter';
}

/// Prints the results and the wall time of each step, also to the job
/// summary.
void report(String? flutter) {
  final text = [
    '### Rollback on Linux, Flutter ${flutter ?? 'pinned by the CLI'}',
    '',
    '| Step | Expected | Runs | Result | Time |',
    '| --- | --- | --- | --- | --- |',
    ...results,
    if (stoppedEarly != null) ...['', '❌ Stopped early: $stoppedEarly'],
    '',
    'Wall time by step: ${timings.join(', ')}',
  ].join('\n');
  print(text);
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null && summary.isNotEmpty) {
    File(summary).writeAsStringSync('$text\n', mode: FileMode.append);
  }
}
