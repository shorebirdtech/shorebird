// cspell:words Xvfb
// ignore_for_file: avoid_print

// End-to-end test of what the updater does when a patch can't boot, and of
// how long a patch takes to boot: the real CLI against a real server, a real
// Flutter build, and the built app launched headless under Xvfb. Linux only
// for now.
//
// It makes one release of a fresh app, without patch signing (so a launch
// checks only the installed patch's size, not its hash), then:
//
//   1. times launches of the release, from process start to the label its
//      main() prints
//   2. publishes patch 1 (good), installs it, and times launches of it
//   3. publishes patch 2 (broken), lets the app download and install it, then
//      zeros the Dart snapshot in the installed file. The file still loads as
//      an ELF of the same size, and the app crashes building its root
//      isolate, before main(): a crash on boot
//   4. launches the app: it must not run patch 2
//   5. launches it again: it must run patch 1, the last patch that booted
//   6. launches it once more, letting the update check finish, then again:
//      it must still run patch 1, so the updater did not install patch 2 again
//
// Step 5 fails on engines in [bootCrashNotRecovered], and the test stops
// there.
//
// The patch's fastest launch may take at most [maxBootRatio] times the
// release's fastest.
//
// Prerequisites: Linux with the Flutter Linux build dependencies and Xvfb;
// Shorebird on PATH and signed in (CI signs in with OIDC).
//
// Usage: dart scripts/boot_recovery_e2e.dart [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// How long one launch may take to finish its update check, and to print its
/// label.
const updateTimeout = Duration(minutes: 3);
const bootTimeout = Duration(minutes: 1);

/// Flutter versions whose engine reports a successful launch before it
/// builds the root isolate from the snapshot, so a patch that crashes there is
/// never marked bad and every launch crashes. null is the Flutter the CLI
/// pins. Measured on 2026-10-24 (e2e run 40133607074).
const bootCrashNotRecovered = {null};

final labelPattern = RegExp('boot-e2e: ');

/// Launches timed for each of the release and patch 1.
const timedLaunches = 5;

/// The most a patch's fastest boot may take, as a multiple of the release's.
/// The fastest of several launches, because a CI runner only ever adds time:
/// one run's launches of the same patch took from 149 to 361 ms.
const maxBootRatio = 1.5;

final results = <String>[];
final timings = <String>[];
bool failed = false;

/// The app this run made, to delete at the end.
String? runAppId;

/// Why the run stopped before checking every case, if it did.
String? stoppedEarly;

Future<void> main(List<String> args) async {
  final flutter = args.isEmpty ? null : args.single;
  final work = Directory.systemTemp.createTempSync('shorebird_boot_');
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

Future<void> run(Directory work, String? flutter) async {
  const patchArgs = ['--allow-asset-diffs', '--allow-native-diffs', '-v'];

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
version: 1.0.0+1
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
      '--no-patch-signing',
      '-v',
    ]),
  );
  final install = Install(
    Directory('${work.path}/install'),
    Directory('${work.path}/install_home')..createSync(),
  );
  final copy = Process.runSync('cp', [
    '-r',
    '${app.path}/build/linux/x64/release/bundle',
    install.bundle.path,
  ]);
  if (copy.exitCode != 0) throw Exception('cp failed: ${copy.stderr}');

  final releaseBoots = await bootTimes(install, 'release');

  setLabel(app, 'good');
  await timed(
    'patch_good',
    () => sh(app, 'shorebird', [
      'patch',
      'linux',
      '--release-version=1.0.0+1',
      ...patchArgs,
    ]),
  );
  await update(install, 'good');
  expect('patch 1 boots', 'good', await boot(install));
  final patchBoots = await bootTimes(install, 'good');

  final releaseFastest = releaseBoots.reduce(min);
  final patchFastest = patchBoots.reduce(min);
  final ratio = patchFastest / releaseFastest;
  results.add(
    '| boot time | patch fastest ≤ ${maxBootRatio}x release | '
    'release ${releaseFastest}ms ($releaseBoots), '
    'patch ${patchFastest}ms ($patchBoots), ${ratio.toStringAsFixed(2)}x '
    '| ${ratio <= maxBootRatio ? 'PASS' : 'FAIL'} |',
  );
  if (ratio > maxBootRatio) failed = true;

  setLabel(app, 'broken');
  await timed(
    'patch_broken',
    () => sh(app, 'shorebird', [
      'patch',
      'linux',
      '--release-version=1.0.0+1',
      ...patchArgs,
    ]),
  );
  await update(install, 'broken');
  zeroSnapshot(installedArtifact(install, 2));

  final (_, crashCode, crashLog) = await launch(
    install,
    until: labelPattern,
    timeout: bootTimeout,
  );
  final crashLabel = label(crashLog);
  results.add(
    '| launch with patch 2 broken | not broken | '
    'runs ${crashLabel ?? 'nothing'}, exit code $crashCode '
    '| ${crashLabel == 'broken' ? 'FAIL' : 'PASS'} |',
  );
  if (crashLabel == 'broken') failed = true;

  final (_, nextCode, nextLog) = await launch(
    install,
    until: labelPattern,
    timeout: bootTimeout,
  );
  final nextLabel = label(nextLog);
  final recovered = nextLabel == 'good';
  final String verdict;
  switch ((recovered, bootCrashNotRecovered.contains(flutter))) {
    case (true, false):
      verdict = 'PASS';
    case (false, true):
      verdict = 'XFAIL (known bug: should run good)';
    case (true, true):
      verdict = 'XPASS: now recovers; update bootCrashNotRecovered';
      failed = true;
    case (false, false):
      verdict = 'FAIL';
      failed = true;
  }
  results.add(
    '| next launch | runs good | '
    'runs ${nextLabel ?? 'nothing'}, exit code $nextCode | $verdict |',
  );
  if (!recovered) {
    print('--- launch with patch 2 broken\n$crashLog');
    print('--- next launch\n$nextLog');
    // The app still boots patch 2, so there is no recovery to check further.
    return;
  }

  final (updated, _, updateLog) = await launch(
    install,
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (!updated) {
    throw Exception(
      "The update check after recovery didn't finish. Its output:\n"
      '$updateLog',
    );
  }
  // Had the updater installed patch 2 again, it would have fresh, loadable
  // bytes and this launch would run it.
  expect('after an update check', 'good', await boot(install));
  results.add('| patch 2 state | Bad | ${patchState(install, 2)} | |');
}

/// A copy of the release's build, with its own updater state.
class Install {
  Install(this.bundle, this.home);
  final Directory bundle;
  final Directory home;
}

/// Launches [install] until its update check finishes, which downloads and
/// installs the patch whose label is [patch].
Future<void> update(Install install, String patch) async {
  final (updated, _, log) = await launch(
    install,
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (!updated) {
    throw Exception(
      "Installing $patch: the update check didn't finish (exited, or ran "
      'past $updateTimeout). Its output:\n$log',
    );
  }
}

/// Launches [install] until it prints its label; returns its output.
Future<String> bootLog(Install install) async {
  final (booted, _, log) = await launch(
    install,
    until: labelPattern,
    timeout: bootTimeout,
  );
  if (!booted) {
    throw Exception(
      'The app printed no label (exited, or ran past $bootTimeout). '
      'Its output:\n$log',
    );
  }
  return log;
}

/// Launches [install] and returns the label it prints.
Future<String?> boot(Install install) async => label(await bootLog(install));

/// Launches [install] [timedLaunches] times, checking each runs [expected],
/// and returns how long each took to print its label, in milliseconds.
Future<List<int>> bootTimes(Install install, String expected) async {
  final times = <int>[];
  for (var i = 0; i < timedLaunches; i++) {
    final stopwatch = Stopwatch()..start();
    final running = await boot(install);
    times.add(stopwatch.elapsedMilliseconds);
    if (running != expected) {
      throw Exception('Timing $expected: launch ${i + 1} runs $running.');
    }
  }
  return times;
}

String? label(String log) =>
    RegExp('boot-e2e: ([a-z_]+)').firstMatch(log)?.group(1);

void expect(String name, String want, String? actual) {
  final pass = actual == want;
  results.add(
    '| $name | runs $want | runs $actual | ${pass ? 'PASS' : 'FAIL'} |',
  );
  print('$name: expected $want, runs $actual');
  if (!pass) failed = true;
}

/// Patch [number]'s state.json in [install]'s updater state, for the report.
String patchState(Install install, int number) {
  final suffix = '/patches/$number/state.json';
  for (final file in install.home.listSync(recursive: true).whereType<File>()) {
    if (file.path.endsWith(suffix)) return file.readAsStringSync().trim();
  }
  return 'none';
}

/// Patch [number]'s installed file in [install]'s updater state.
File installedArtifact(Install install, int number) {
  final suffix = '/patches/$number/dlc.vmcode';
  for (final file in install.home.listSync(recursive: true).whereType<File>()) {
    if (file.path.endsWith(suffix)) return file;
  }
  throw Exception('Patch $number is not installed under ${install.home}.');
}

/// Overwrites the VM snapshot in the ELF [file] with zeros, in place. Dart
/// 3.13 merged it with the isolate snapshot into _kDartSnapshotData.
void zeroSnapshot(File file) {
  const symbolNames = {'_kDartSnapshotData', '_kDartVmSnapshotData'};
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  int u16(int at) => data.getUint16(at, Endian.little);
  int u32(int at) => data.getUint32(at, Endian.little);
  int u64(int at) => data.getUint64(at, Endian.little);
  String name(int at) => ascii.decode(bytes.sublist(at, bytes.indexOf(0, at)));

  // ELF64 section headers: offset, entry size and count from the file header.
  final sections = [
    for (var i = 0; i < u16(0x3c); i++) u64(0x28) + i * u16(0x3a),
  ];
  const dynsymType = 11;
  final dynsym = sections.firstWhere((s) => u32(s + 4) == dynsymType);
  final strings = u64(sections[u32(dynsym + 40)] + 24);
  // ELF64 symbols are 24 bytes: name, info, other, section, value, size.
  for (
    var at = u64(dynsym + 24);
    at < u64(dynsym + 24) + u64(dynsym + 32);
    at += 24
  ) {
    final symbolName = name(strings + u32(at));
    if (!symbolNames.contains(symbolName)) continue;
    final section = sections[u16(at + 6)];
    final offset = u64(section + 24) + u64(at + 8) - u64(section + 16);
    final size = u64(at + 16);
    bytes.fillRange(offset, offset + size, 0);
    file.writeAsBytesSync(bytes);
    print('Zeroed $size bytes of $symbolName at $offset in ${file.path}.');
    return;
  }
  throw Exception('${file.path} has none of $symbolNames.');
}

/// Runs [install] until a line of its output matches [until], it exits, or
/// [timeout] passes, then stops it. Returns whether a line matched, its exit
/// code, and its output.
Future<(bool, int, String)> launch(
  Install install, {
  required RegExp until,
  required Duration timeout,
}) async {
  final process = await Process.start(
    '${install.bundle.path}/e2e_test',
    [],
    environment: {'HOME': install.home.path, 'DISPLAY': ':99'},
  );
  final output = StringBuffer();
  final matched = Completer<bool>();
  void onLine(String line) {
    output.writeln(line);
    if (!matched.isCompleted && until.hasMatch(line)) matched.complete(true);
  }

  final streams = [
    for (final stream in [process.stdout, process.stderr])
      stream
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
  final code = await process.exitCode;
  for (final s in streams) {
    await s.cancel();
  }
  return (found, code, output.toString());
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
  ).writeAsStringSync("void main() { print('boot-e2e: $label'); }\n");
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
  final version = flutter ?? 'pinned by the CLI';
  final text = [
    '### Boot recovery and boot time on Linux, Flutter $version',
    '',
    '| Check | Expected | Actual | Result |',
    '| --- | --- | --- | --- |',
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
