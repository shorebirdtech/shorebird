// cspell:words Xvfb
// ignore_for_file: avoid_print

// What the end-to-end scripts in this directory share: making a fresh app on
// the server under test, running commands, launching the built app and
// reading what it prints, and the report at the end. Not a test itself.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How long one launch may take to finish its update check, and to print its
/// label.
const updateTimeout = Duration(minutes: 3);
const bootTimeout = Duration(minutes: 1);

/// The rows of the report's table, one per check.
final results = <String>[];

/// The wall time of each step, for the report.
final timings = <String>[];

/// Whether a check failed. The run exits 1 at the end if so.
bool failed = false;

/// Why the run stopped before it finished, if it did.
String? stoppedEarly;

/// The app [createApp] made, to delete at the end.
String? _appId;

/// Runs [body]. Then, also when the job is cancelled or times out, prints the
/// report (a table titled [title] with [columns] and the rows in [results]),
/// deletes the app [createApp] made, and runs [tearDown]. Exits 1 if [body]
/// threw or a check failed.
Future<void> runE2e({
  required String title,
  required List<String> columns,
  required Future<void> Function() body,
  Future<void> Function()? tearDown,
}) async {
  Future<void> cleanUp() async {
    report(title, columns);
    final appId = _appId;
    _appId = null;
    if (appId != null) {
      // Each run mints an app; delete it so the e2e account's app list stays
      // flat (see patch_e2e.dart).
      print('Deleting e2e app $appId');
      final result = await Process.run('shorebird', [
        'api',
        '-X',
        'DELETE',
        'apps/$appId',
      ], runInShell: Platform.isWindows);
      if (result.exitCode != 0) {
        print('⚠️  Failed to delete e2e app $appId: ${result.stderr}');
      }
    }
    await tearDown?.call();
  }

  // A cancelled or timed-out job is signaled, which skips `finally`. Dart
  // can't watch SIGTERM on Windows.
  final signals = [
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ])
      signal.watch().listen((_) async {
        stoppedEarly = 'got $signal';
        await cleanUp();
        exit(1);
      }),
  ];
  try {
    await body();
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

/// Prints the results and the wall time of each step, also to the job
/// summary.
void report(String title, List<String> columns) {
  final text = [
    '### $title',
    '',
    '| ${columns.join(' | ')} |',
    '|${' --- |' * columns.length}',
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

/// Makes a fresh app, `e2e_test` in [work], for [platform] at
/// [version], printing the label `release`, with Shorebird initialized
/// against the server under test (SHOREBIRD_HOSTED_URL, dev by default). It
/// is deleted when the run ends.
///
/// Set SHOREBIRD_ORG_ID to choose the organization for the app when the
/// account can create apps in more than one.
Future<Directory> createApp(
  Directory work,
  String platform, {
  required String version,
}) async {
  await timed(
    'create',
    () => sh(work, pinnedFlutter(), [
      'create',
      'e2e_test',
      '--org',
      'com.example.e2e_test',
      '--empty',
      '--platforms',
      platform,
    ]),
  );
  final app = Directory('${work.path}/e2e_test');
  // `flutter create` writes the pinned Flutter's SDK constraint and lints,
  // which older Flutter versions can't resolve.
  File('${app.path}/pubspec.yaml').writeAsStringSync('''
name: e2e_test
version: $version
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  flutter:
    sdk: flutter
''');
  File('${app.path}/analysis_options.yaml').deleteSync();
  setLabel(app, 'release');
  final orgId = Platform.environment['SHOREBIRD_ORG_ID'];
  await timed(
    'init',
    () => sh(app, 'shorebird', [
      'init',
      '--force',
      if (orgId != null) '--org-id=$orgId',
      '-v',
    ]),
  );
  final hostedUrl =
      Platform.environment['SHOREBIRD_HOSTED_URL'] ??
      'https://api-dev.shorebird.dev';
  final shorebirdYaml = File('${app.path}/shorebird.yaml')
    ..writeAsStringSync('base_url: $hostedUrl\n', mode: FileMode.append);
  _appId = RegExp(
    r'app_id: (\S+)',
  ).firstMatch(shorebirdYaml.readAsStringSync())!.group(1);
  return app;
}

/// Makes the app print `e2e-label: <label>` when it starts.
void setLabel(Directory app, String label) {
  File(
    '${app.path}/lib/main.dart',
  ).writeAsStringSync("void main() { print('e2e-label: $label'); }\n");
}

/// The label the app printed in [log], if it printed one.
String? labelIn(String log) =>
    RegExp(r'e2e-label: (\S+)').firstMatch(log)?.group(1);

void setVersion(Directory app, String version) {
  final pubspec = File('${app.path}/pubspec.yaml');
  pubspec.writeAsStringSync(
    pubspec.readAsStringSync().replaceFirst(
      RegExp('^version: .*', multiLine: true),
      'version: $version',
    ),
  );
}

/// Launches an installed app and returns once a line of its output matches
/// [until] (true), or it exits or [timeout] passes (false), with its output.
/// The app is stopped before this returns.
typedef Launch =
    Future<(bool, String)> Function({
      required RegExp until,
      required Duration timeout,
    });

/// Launches the app twice with [launch]: once to check for an update and
/// install what the server serves, then once to boot. Throws, naming [name],
/// if either launch doesn't get that far. Returns both launches' output and
/// the label the app printed when it booted.
Future<({String updateLog, String bootLog, String label})> updateAndBoot(
  String name,
  Launch launch,
) async {
  final (updated, updateLog) = await launch(
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (!updated) {
    throw Exception(
      "$name: the update check didn't finish (exited, or ran past "
      '$updateTimeout). Its output:\n$updateLog',
    );
  }
  final (booted, bootLog) = await launch(
    until: RegExp('e2e-label: '),
    timeout: bootTimeout,
  );
  if (!booted) {
    throw Exception(
      '$name: the app printed no label (exited, or ran past $bootTimeout). '
      'Its output:\n$bootLog',
    );
  }
  return (updateLog: updateLog, bootLog: bootLog, label: labelIn(bootLog)!);
}

/// The X display the Linux app is run on, headless.
const _display = ':99';

/// Starts the headless X server Linux apps are launched on. Kill it at the
/// end.
Future<Process> startXvfb() => Process.start('Xvfb', [
  _display,
  '-screen',
  '0',
  '1024x768x24',
], mode: ProcessStartMode.inheritStdio);

/// Starts the Linux app in [bundle] on the [startXvfb] display, with [home]
/// as its HOME, where the updater keeps its state.
Future<Process> startLinux(Directory bundle, Directory home) => Process.start(
  '${bundle.path}/e2e_test',
  [],
  environment: {'HOME': home.path, 'DISPLAY': _display},
);

/// Launches the Linux app in [bundle] with [startLinux]. See [Launch].
Future<(bool, String)> launchLinux(
  Directory bundle,
  Directory home, {
  required RegExp until,
  required Duration timeout,
}) async =>
    watch(await startLinux(bundle, home), until: until, timeout: timeout);

/// Reads [process]'s output until a line matches [until], it exits, or
/// [timeout] passes, then kills it. Returns whether a line matched, and the
/// output.
Future<(bool, String)> watch(
  Process process, {
  required RegExp until,
  required Duration timeout,
}) async {
  final output = StringBuffer();
  final matched = Completer<bool>();
  void onLine(String line) {
    output.writeln(line);
    if (!matched.isCompleted && until.hasMatch(line)) matched.complete(true);
  }

  // adb logcat sometimes lets through bytes that aren't UTF-8.
  const decoder = Utf8Decoder(allowMalformed: true);
  final streams = [
    for (final stream in [process.stdout, process.stderr])
      stream.transform(decoder).transform(const LineSplitter()).listen(onLine),
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
    // Finds shorebird.bat and flutter.bat.
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw Exception('$executable ${args.join(' ')} exited with $code.');
  }
}

/// Runs [body], recording its wall time under [name] for the report.
Future<void> timed(String name, Future<void> Function() body) async {
  final stopwatch = Stopwatch()..start();
  await body();
  timings.add('$name ${stopwatch.elapsed.inSeconds}s');
}

/// The Flutter the CLI pins, for `flutter create`; not the version under test.
String pinnedFlutter() {
  final root = File(Platform.script.toFilePath()).parent.parent.path;
  final revision = File(
    '$root/bin/internal/flutter.version',
  ).readAsStringSync().trim();
  final flutter = Platform.isWindows ? 'flutter.bat' : 'flutter';
  return '$root/bin/cache/flutter/$revision/bin/$flutter';
}
