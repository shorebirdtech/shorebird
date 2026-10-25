// cspell:words xfail XPASS dynsym logcat pidof
// ignore_for_file: avoid_print

// End-to-end test of what the updater does when a patch crashes the app at
// boot, and of how long a patch takes to boot: the real CLI against a real
// server, a real Flutter build, and the built app launched. Runs on Linux (the
// app headless under Xvfb) and Android (on the one emulator adb sees, which
// must let adb run as root).
//
// It makes a release of a fresh app without patch signing (so a launch checks
// only the installed patch's size, not its hash), then:
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
//   6. makes a release with the default, a Shorebird-managed key, and a 16 MiB
//      string in the app, installs it in place of the first, and times its
//      launches and a patch's: the updater hashes a signed patch at every
//      launch
//
// Step 5 is a known failure on engines in [bootCrashNotRecovered], as long
// as the app crashes again there.
//
// In steps 2 and 6 the patch's third-fastest launch may take at most
// [maxBootRatio] times the release's. The app only prints, so step 2 times the
// engine's and updater's own startup with a patch. Step 6 adds a bigger app
// and the hash; it bounds their cost but doesn't separate the two.
//
// Prerequisites: Shorebird on PATH and signed in (CI signs in with OIDC), and
// per platform: on Linux the Flutter Linux build dependencies and Xvfb; for
// Android the Android SDK and a running emulator.
//
// Usage: dart scripts/boot_recovery_e2e.dart <linux|android> [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'e2e_helpers.dart';

/// Flutter versions whose engine reports a successful launch before it
/// builds the root isolate from the snapshot, so a patch that crashes there is
/// never marked bad and every launch crashes. null is the Flutter the CLI
/// pins. Measured on 2026-10-24 on Linux (e2e run 40133607074) and Android
/// (e2e run 40141450017).
const bootCrashNotRecovered = {null};

/// Launches timed for each release and patch.
const timedLaunches = 10;

/// The most a patch's third-fastest boot may take, as a multiple of the
/// release's. Not the median: a CI runner only ever adds time, and one run's
/// launches of the same patch took from 149 to 361 ms. Not the fastest: one
/// fast outlier would set the bound alone, as an emulator release launch of
/// 114 ms did against 158 to 212 for the rest.
const maxBootRatio = 1.5;

/// The third-fastest of [boots], in milliseconds.
int typical(List<int> boots) => (boots.toList()..sort())[2];

final labelPattern = RegExp('e2e-label: ');

Future<void> main(List<String> args) async {
  final install = switch (args.firstOrNull) {
    'linux' => LinuxInstall(),
    'android' => AndroidInstall(),
    _ => null,
  };
  if (install == null || args.length > 2) {
    print(
      'Usage: dart scripts/boot_recovery_e2e.dart <linux|android> '
      '[<flutter-version>]',
    );
    exit(64);
  }
  final flutter = args.length == 2 ? args[1] : null;
  final work = Directory.systemTemp.createTempSync('shorebird_boot_');
  await install.setUp(work);
  await runE2e(
    title:
        'Boot recovery and boot time on ${install.title}, '
        'Flutter ${flutter ?? 'pinned by the CLI'}',
    columns: ['Check', 'Expected', 'Actual', 'Result'],
    body: () => run(work, install, flutter),
    tearDown: install.tearDown,
  );
}

Future<void> run(Directory work, Install install, String? flutter) async {
  const patchArgs = ['--allow-asset-diffs', '--allow-native-diffs', '-v'];
  final app = await createApp(work, install.platform, version: '1.0.0+1');
  await timed(
    'release',
    () => sh(app, 'shorebird', [
      'release',
      install.platform,
      ...install.releaseArgs,
      if (flutter != null) '--flutter-version=$flutter',
      '--no-patch-signing',
      '-v',
    ]),
  );
  await install.install(app);

  Future<void> patch(String label) async {
    setLabel(app, label);
    await timed(
      'patch_$label',
      () => sh(app, 'shorebird', [
        'patch',
        install.platform,
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

  checkBootTime('boot time', releaseBoots, patchBoots);

  await checkCrashRecovery(install, flutter, () => patch('broken'));
  await checkSignedBootTime(app, install, flutter);
}

/// Checks that the patch's [typical] boot took at most [maxRatio] times the
/// release's.
void checkBootTime(
  String name,
  List<int> releaseBoots,
  List<int> patchBoots, {
  double maxRatio = maxBootRatio,
}) {
  final release = typical(releaseBoots);
  final patch = typical(patchBoots);
  final ratio = patch / release;
  results.add(
    '| $name | patch ≤ ${maxRatio}x release, third-fastest | '
    'release ${release}ms ($releaseBoots), '
    'patch ${patch}ms ($patchBoots), ${ratio.toStringAsFixed(2)}x '
    '| ${ratio <= maxRatio ? 'PASS' : 'FAIL'} |',
  );
  if (ratio > maxRatio) failed = true;
}

/// Publishes patch 2 with [publish], breaks it once installed, and checks the
/// app crashes on it and then recovers.
Future<void> checkCrashRecovery(
  Install install,
  String? flutter,
  Future<void> Function() publish,
) async {
  await publish();
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
  await install.breakPatch(2);

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

/// Size of the string [checkSignedBootTime] builds into the app.
const blobBytes = 16 << 20;

/// Times boots of a release made with the default, a Shorebird-managed key,
/// and of a patch to it. The updater checks a signed patch's hash at every
/// launch, so the app carries a [blobBytes] string to make that cost show.
/// Installs the release in place of the one the other checks used.
Future<void> checkSignedBootTime(
  Directory app,
  Install install,
  String? flutter,
) async {
  File('${app.path}/lib/blob.dart').writeAsStringSync(
    "const blob = '${'0123456789abcdef' * (blobBytes ~/ 16)}';\n",
  );
  void label(String label) =>
      File('${app.path}/lib/main.dart')
      // Read at run time, so the compiler keeps the string.
      .writeAsStringSync('''
import 'blob.dart';
void main() {
  print('e2e-label: $label \${blob.codeUnitAt(DateTime.now().second)}');
}
''');
  label('signed_release');
  setVersion(app, '1.0.0+2');
  await timed(
    'release_signed',
    () => sh(app, 'shorebird', [
      'release',
      install.platform,
      ...install.releaseArgs,
      if (flutter != null) '--flutter-version=$flutter',
      '-v',
    ]),
  );
  // Without the key the updater skips the check, and this would time no hash.
  if (!(await install.builtShorebirdYaml(app)).contains('patch_public_key')) {
    throw Exception('The managed release embedded no public key.');
  }
  await install.install(app);
  final releaseBoots = await bootTimes(install, 'signed_release');

  label('signed');
  await timed(
    'patch_signed',
    () => sh(app, 'shorebird', [
      'patch',
      install.platform,
      '--release-version=1.0.0+2',
      '--allow-asset-diffs',
      '--allow-native-diffs',
      '-v',
    ]),
  );
  final signed = await updateAndBoot('signed patch', install.launch);
  expect('signed patch boots', 'signed', signed.label);
  final patchBoots = await bootTimes(install, 'signed');
  checkBootTime(
    'boot time, signed, ${blobBytes >> 20} MiB string',
    releaseBoots,
    patchBoots,
    maxRatio: install.maxSignedBootRatio,
  );
}

/// The one install of the app this run checks, on one platform. Its updater
/// state starts empty.
abstract class Install {
  /// The platform, as `flutter create` and `shorebird release` name it.
  String get platform;

  String get title;

  List<String> get releaseArgs => const [];

  /// The bound for step 6, a signed patch's boot against its release's.
  double get maxSignedBootRatio => maxBootRatio;

  late Directory work;

  Future<void> setUp(Directory work) async => this.work = work;

  Future<void> tearDown() async {}

  /// Installs the release just built from [app].
  Future<void> install(Directory app);

  /// The shorebird.yaml the release just built from [app] carries.
  Future<String> builtShorebirdYaml(Directory app);

  /// Launches the app and stops it once a line matches [until], or it ends
  /// or [timeout] passes, recording how long it took and how it ended.
  Future<Run> run({required RegExp until, required Duration timeout});

  /// [run] as a [Launch].
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  }) async {
    final launched = await run(until: until, timeout: timeout);
    return (launched.matched, launched.log);
  }

  /// Zeros the snapshot in installed patch [number] (see [zeroSnapshot]).
  Future<void> breakPatch(int number);
}

/// A copy of the release's build, with its updater state in its own HOME.
class LinuxInstall extends Install {
  Process? _xvfb;
  late final Directory _bundle = Directory('${work.path}/install');
  late final Directory _home = Directory('${work.path}/install_home');

  @override
  String get platform => 'linux';

  @override
  String get title => 'Linux';

  @override
  Future<String> builtShorebirdYaml(Directory app) async => File(
    '${app.path}/build/linux/x64/release/bundle/data/flutter_assets/'
    'shorebird.yaml',
  ).readAsStringSync();

  @override
  Future<void> setUp(Directory work) async {
    await super.setUp(work);
    _xvfb = await startXvfb();
  }

  @override
  Future<void> tearDown() async => _xvfb?.kill();

  /// Replaces any earlier install, and its updater state.
  @override
  Future<void> install(Directory app) async {
    for (final dir in [_bundle, _home]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
    _home.createSync();
    await sh(work, 'cp', [
      '-r',
      '${app.path}/build/linux/x64/release/bundle',
      _bundle.path,
    ]);
  }

  @override
  Future<Run> run({required RegExp until, required Duration timeout}) async {
    final stopwatch = Stopwatch()..start();
    final process = await startLinux(_bundle, _home);
    final (matched, log) = await watch(
      process,
      until: until,
      timeout: timeout,
    );
    final elapsed = stopwatch.elapsed;
    final exitCode = await process.exitCode;
    // watch stops the app with SIGTERM once a line matches or the timeout
    // passes; any other signal is the app's own.
    final crashed =
        !matched &&
        exitCode < 0 &&
        exitCode != -ProcessSignal.sigterm.signalNumber;
    return Run(
      matched: matched,
      log: log,
      crashed: crashed,
      ending: crashed
          ? 'crashed with signal ${-exitCode}'
          : 'exit code $exitCode',
      elapsed: elapsed,
    );
  }

  @override
  Future<void> breakPatch(int number) async {
    final suffix = '/patches/$number/dlc.vmcode';
    for (final file in _home.listSync(recursive: true).whereType<File>()) {
      if (file.path.endsWith(suffix)) return zeroSnapshot(file);
    }
    throw Exception('Patch $number is not installed under $_home.');
  }
}

/// The app installed on the emulator. Its updater state is in the app's
/// private storage, which only root can write from adb.
class AndroidInstall extends Install {
  static const package = 'com.example.e2e_test.e2e_test';

  @override
  String get platform => 'android';

  @override
  String get title => 'Android';

  @override
  List<String> get releaseArgs => const ['--artifact=apk'];

  /// On the CI emulator the hash of a 16 MiB patch at launch added 41 and 80
  /// ms (1.29x, then 1.61x; e2e runs 40148536352, 40150677616), against 0 to
  /// 14 ms on a Linux runner. The emulator likely lacks SHA hardware
  /// acceleration, so this isn't a phone's cost. Revisit once a real phone's
  /// signed boot time has been measured.
  @override
  double get maxSignedBootRatio => 2;

  File _apk(Directory app) =>
      File('${app.path}/build/app/outputs/flutter-apk/app-release.apk');

  @override
  Future<String> builtShorebirdYaml(Directory app) async {
    final result = await Process.run('unzip', [
      '-p',
      _apk(app).path,
      'assets/flutter_assets/shorebird.yaml',
    ]);
    if (result.exitCode != 0) throw Exception('unzip: ${result.stderr}');
    return result.stdout as String;
  }

  @override
  Future<void> setUp(Directory work) async {
    await super.setUp(work);
    await sh(work, 'adb', ['root']);
    await sh(work, 'adb', ['wait-for-device']);
  }

  /// Installs the release in place of any earlier one, clearing the updater's
  /// state.
  @override
  Future<void> install(Directory app) async {
    // Fails when it isn't installed.
    await Process.run('adb', ['uninstall', package]);
    await sh(work, 'adb', ['install', _apk(app).path]);
  }

  @override
  Future<Run> run({required RegExp until, required Duration timeout}) async {
    // The crash buffer holds this launch's crash, if it has one.
    await sh(work, 'adb', ['logcat', '-b', 'crash', '-c']);
    // -W waits for the activity's first frame, which this app never draws,
    // so it returns after its 10 s timeout. The app has a pid by then unless
    // it died.
    await sh(work, 'adb', [
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '$package/.MainActivity',
    ]);
    // pidof finds nothing, and exits 1, if the app already died.
    final pid = (await Process.run('adb', [
      'shell',
      'pidof',
      package,
    ])).stdout.toString().trim();
    var matched = false;
    var log = '';
    if (pid.isNotEmpty) {
      // This launch's lines from the process's first, with the device's
      // timestamps.
      final logcat = await Process.start('adb', [
        'logcat',
        '-v',
        'epoch',
        '--pid=$pid',
      ]);
      try {
        (matched, log) = await watch(logcat, until: until, timeout: timeout);
      } finally {
        await sh(work, 'adb', ['shell', 'am', 'force-stop', package]);
      }
    }
    final crash = (await Process.run('adb', [
      'logcat',
      '-b',
      'crash',
      '-d',
    ])).stdout.toString();
    final crashed = !matched && crash.contains(package);
    final signal = RegExp(r'signal (\d+) \((\w+)\)').firstMatch(crash);
    return Run(
      matched: matched,
      log: crash.isEmpty ? log : '$log\n--- crash buffer\n$crash',
      crashed: crashed,
      ending: crashed
          ? 'crashed${signal == null ? '' : ' with ${signal.group(2)}'}'
          : pid.isEmpty
          ? 'exited right after it started'
          : 'no crash logged',
      elapsed: matched ? _bootTime(log, until) : null,
    );
  }

  /// From the process's first log line to the first line matching [until],
  /// by the device's clock.
  static Duration _bootTime(String log, RegExp until) {
    // Skips lines with no timestamp, such as "--------- beginning of main".
    final timestamp = RegExp(r'^\s*(\d+\.\d+) ');
    final lines = log.split('\n').where(timestamp.hasMatch);
    double seconds(String line) =>
        double.parse(timestamp.firstMatch(line)!.group(1)!);
    final start = seconds(lines.first);
    final end = seconds(lines.firstWhere(until.hasMatch));
    return Duration(microseconds: ((end - start) * 1e6).round());
  }

  /// Copies the patch off the device, zeros it, and writes it back through
  /// the existing file, which keeps its owner, mode and SELinux label.
  @override
  Future<void> breakPatch(int number) async {
    final found = await Process.run('adb', [
      'shell',
      'find',
      '/data/data/$package',
      '-path',
      "'*/patches/$number/dlc.vmcode'",
    ]);
    final path = found.stdout.toString().trim();
    if (path.isEmpty || path.contains('\n')) {
      throw Exception('Patch $number is not installed: "$path".');
    }
    final local = File('${work.path}/dlc.vmcode');
    await sh(work, 'adb', ['pull', path, local.path]);
    zeroSnapshot(local);
    const staged = '/data/local/tmp/dlc.vmcode';
    await sh(work, 'adb', ['push', local.path, staged]);
    await sh(work, 'adb', ['shell', 'cat $staged > $path && rm $staged']);
  }
}

/// One launch of the app, from [Install.run].
class Run {
  Run({
    required this.matched,
    required this.log,
    required this.crashed,
    required this.ending,
    required this.elapsed,
  });

  /// Whether a line matched what the launch waited for.
  final bool matched;
  final String log;

  /// Whether the app crashed, rather than being stopped.
  final bool crashed;

  /// How the launch ended, for the report.
  final String ending;

  /// From the start of the process to the matching line, if one matched: on
  /// Linux by the host's clock from launch, on Android by the device's from
  /// the process's first log line.
  final Duration? elapsed;

  String get description => 'runs ${labelIn(log) ?? 'nothing'}, $ending';
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
    times.add(launch.elapsed!.inMilliseconds);
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
