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
// Booting patch 2 deletes patch 1 from disk, so rolling back 2 downloads 1
// afresh: that step passes on the server's response alone. An updater that
// ignores the rollback signal keeps patch 2 installed, so it fails the roll
// forward (2 isn't downloaded again) and the roll back to the release.
//
// Prerequisites: Linux with the Flutter Linux build dependencies and Xvfb;
// Shorebird on PATH and signed in (CI signs in with OIDC).
//
// Usage: dart scripts/patch_rollback_e2e.dart [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:io';

import 'e2e_helpers.dart';

const releaseVersion = '1.0.0+1';

Future<void> main(List<String> args) async {
  final flutter = args.isEmpty ? null : args.single;
  final work = Directory.systemTemp.createTempSync('shorebird_rollback_');
  final xvfb = await startXvfb();
  await runE2e(
    title: 'Rollback on Linux, Flutter ${flutter ?? 'pinned by the CLI'}',
    columns: ['Step', 'Expected', 'Runs', 'Result', 'Time'],
    body: () => run(work, flutter),
    tearDown: () async => xvfb.kill(),
  );
}

/// Makes the app, its release and patches, and checks the install after each
/// step.
Future<void> run(Directory work, String? flutter) async {
  final app = await createApp(work, 'linux', version: releaseVersion);
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
}) => timed(
  '${rolledBack ? 'rollback' : 'rollforward'}_$number',
  () => sh(app, 'shorebird', [
    'patches',
    if (rolledBack) 'rollback' else 'rollforward',
    '--release-version=$releaseVersion',
    '--patch-number=$number',
    '--require-change',
  ]),
);

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
  final (:updateLog, :bootLog, label: running) = await updateAndBoot(
    step,
    ({required until, required timeout}) =>
        launchLinux(install, home, until: until, timeout: timeout),
  );
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
