// cspell:words xfail XPASS dynsym
// ignore_for_file: avoid_print

// End-to-end test of what the updater does when a patch crashes the app at
// boot, and of how long a patch takes to boot: the real CLI against a real
// server, a real Flutter build, and the built app launched. Linux only for
// now; the app is run headless under Xvfb.
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
//   4. launches the app: it must crash
//   5. launches it again: it must run patch 1, the last patch that booted
//
// Step 5 is a known failure on engines in [bootCrashNotRecovered], as long
// as the app crashes again there.
//
// The patch's fastest launch may take at most [maxBootRatio] times the
// release's fastest. The app only prints, so this times the engine's and
// updater's own startup with a patch.
//
// Prerequisites: Linux with the Flutter Linux build dependencies and Xvfb;
// Shorebird on PATH and signed in (CI signs in with OIDC).
//
// Usage: dart scripts/boot_recovery_e2e.dart [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'e2e_helpers.dart';

/// Flutter versions whose engine reports a successful launch before it
/// builds the root isolate from the snapshot, so a patch that crashes there is
/// never marked bad and every launch crashes. null is the Flutter the CLI
/// pins. Measured on 2026-10-24 (e2e run 40133607074).
const bootCrashNotRecovered = {null};

/// Launches timed for each of the release and patch 1.
const timedLaunches = 5;

/// The most a patch's fastest boot may take, as a multiple of the release's.
/// The fastest of several launches, because a CI runner only ever adds time:
/// one run's launches of the same patch took from 149 to 361 ms.
const maxBootRatio = 1.5;

final labelPattern = RegExp('e2e-label: ');

Future<void> main(List<String> args) async {
  final flutter = args.isEmpty ? null : args.single;
  final work = Directory.systemTemp.createTempSync('shorebird_boot_');
  final xvfb = await startXvfb();
  final install = Install(
    Directory('${work.path}/install'),
    Directory('${work.path}/install_home')..createSync(),
  );
  await runE2e(
    title:
        'Boot recovery and boot time on Linux, '
        'Flutter ${flutter ?? 'pinned by the CLI'}',
    columns: ['Check', 'Expected', 'Actual', 'Result'],
    body: () => run(work, install, flutter),
    tearDown: () async => xvfb.kill(),
  );
}

Future<void> run(Directory work, Install install, String? flutter) async {
  const patchArgs = ['--allow-asset-diffs', '--allow-native-diffs', '-v'];
  final app = await createApp(work, 'linux', version: '1.0.0+1');
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
  await sh(work, 'cp', [
    '-r',
    '${app.path}/build/linux/x64/release/bundle',
    install.bundle.path,
  ]);

  Future<void> patch(String label) async {
    setLabel(app, label);
    await timed(
      'patch_$label',
      () => sh(app, 'shorebird', [
        'patch',
        'linux',
        '--release-version=1.0.0+1',
        ...patchArgs,
      ]),
    );
  }

  final releaseBoots = await bootTimes(install, 'release');
  await patch('good');
  final good = await updateAndBoot('patch 1', install.launch);
  expect('patch 1 boots', 'good', good.label);
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

  await patch('broken');
  final (updated, updateLog) = await install.launch(
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (!updated) {
    throw Exception(
      "Installing patch 2: the update check didn't finish. Its output:\n"
      '$updateLog',
    );
  }
  zeroSnapshot(install.artifact(2));

  // If patch 2 didn't crash, the next launch proves nothing about recovery.
  final crash = await install.run(until: labelPattern, timeout: bootTimeout);
  results.add(
    '| launch with patch 2 broken | crashes | ${crash.description} '
    '| ${crash.crashed ? 'PASS' : 'FAIL'} |',
  );
  if (!crash.crashed) {
    failed = true;
    print('--- launch with patch 2 broken\n${crash.log}');
    return;
  }

  final next = await install.run(until: labelPattern, timeout: bootTimeout);
  final recovered = labelIn(next.log) == 'good';
  final String verdict;
  switch ((recovered, bootCrashNotRecovered.contains(flutter))) {
    case (true, false):
      verdict = 'PASS';
    // Only the known bug, the same crash again, is expected.
    case (false, true) when next.crashed:
      verdict = 'XFAIL (known bug: crashes again)';
    case (true, true):
      verdict = 'XPASS: now recovers; update bootCrashNotRecovered';
      failed = true;
    case _:
      verdict = 'FAIL';
      failed = true;
  }
  results.add('| next launch | runs good | ${next.description} | $verdict |');
  if (verdict == 'FAIL' || verdict.startsWith('XPASS')) {
    print('--- launch with patch 2 broken\n${crash.log}');
    print('--- next launch\n${next.log}');
  }
}

/// A copy of the release's build, with its updater state in its own HOME.
class Install {
  Install(this.bundle, this.home);
  final Directory bundle;
  final Directory home;

  /// Launches the app; see [Launch].
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  }) => launchLinux(bundle, home, until: until, timeout: timeout);

  /// Launches the app like [launch], also recording how long it ran and how
  /// it ended.
  Future<Run> run({required RegExp until, required Duration timeout}) async {
    final stopwatch = Stopwatch()..start();
    final process = await startLinux(bundle, home);
    final (matched, log) = await watch(
      process,
      until: until,
      timeout: timeout,
    );
    return Run(
      matched: matched,
      log: log,
      exitCode: await process.exitCode,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Patch [number]'s installed file in the updater's state.
  File artifact(int number) {
    final suffix = '/patches/$number/dlc.vmcode';
    for (final file in home.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith(suffix)) return file;
    }
    throw Exception('Patch $number is not installed under $home.');
  }
}

/// One launch of the app, from [Install.run].
class Run {
  Run({
    required this.matched,
    required this.log,
    required this.exitCode,
    required this.elapsed,
  });

  /// Whether a line matched what the launch waited for. If so, [watch]
  /// stopped the app.
  final bool matched;
  final String log;
  final int exitCode;
  final Duration elapsed;

  /// Whether the app died of a signal it didn't get from [watch], which
  /// stops it with SIGTERM once a line matches or the timeout passes.
  bool get crashed =>
      !matched &&
      exitCode < 0 &&
      exitCode != -ProcessSignal.sigterm.signalNumber;

  String get description =>
      'runs ${labelIn(log) ?? 'nothing'}, '
      '${crashed ? 'crashed with signal ${-exitCode}' : 'exit code $exitCode'}';
}

/// Launches the app [timedLaunches] times, checking each runs [expected], and
/// returns how long each took to print its label, in milliseconds.
Future<List<int>> bootTimes(Install install, String expected) async {
  final times = <int>[];
  for (var i = 0; i < timedLaunches; i++) {
    final launch = await install.run(until: labelPattern, timeout: bootTimeout);
    if (!launch.matched || labelIn(launch.log) != expected) {
      throw Exception(
        'Timing $expected: launch ${i + 1} ${launch.description}. '
        'Its output:\n${launch.log}',
      );
    }
    times.add(launch.elapsed.inMilliseconds);
  }
  return times;
}

void expect(String name, String want, String? actual) {
  final pass = actual == want;
  results.add(
    '| $name | runs $want | runs $actual | ${pass ? 'PASS' : 'FAIL'} |',
  );
  print('$name: expected $want, runs $actual');
  if (!pass) failed = true;
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
