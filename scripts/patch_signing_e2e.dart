// cspell:words genrsa pubout Xvfb xfail XPASS logcat libexec LOCALAPPDATA
// ignore_for_file: avoid_print

// End-to-end test of patch signing: the real CLI against a real server, a
// real Flutter build, and the built app launched, checking which code it runs
// after it downloads each patch. Runs on Linux (the app headless under Xvfb),
// macOS, Windows, and Android (on the one emulator or device adb sees).
//
// It makes two releases of a fresh app:
//
//   1.0.0+1  with the customer's key A, then three patches:
//            signed with key B   -> wrong_key
//            unsigned            -> unsigned
//            signed with key A   -> valid
//   1.0.0+2  with the default, a Shorebird-managed key, then one patch
//            signed by Shorebird -> managed
//
// On Linux and macOS each release is installed twice: strict (the signature
// is checked at every launch) and install_only (checked once, at install). A
// device holds one install of an app, so Android checks strict only, and so
// does Windows, where every app shares one updater state (see WindowsTarget);
// install_only is the updater's own logic, the same on every platform. Each
// patch prints its own label, so after each patch every install is launched
// twice (download and install, then boot), and the label it prints says
// whether it ran the patch. An install's updater state lasts across its
// launches, so a refused patch stays marked bad, as on a device.
//
// Set SHOREBIRD_ORG_ID to choose the organization for the app when the
// account can create apps in more than one.
//
// Prerequisites: Shorebird on PATH and signed in (CI signs in with OIDC),
// openssl, and per platform: on Linux the Flutter Linux build dependencies and
// Xvfb; on macOS Xcode; on Windows Visual Studio with the C++ desktop
// workload; for Android the Android SDK and a running emulator. On Windows it
// deletes the updater's state from %LOCALAPPDATA% (see WindowsTarget), so it
// runs only where CI is set: on a throwaway machine.
//
// Usage: dart scripts/patch_signing_e2e.dart <linux|macos|windows|android>
//     [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:io';

import 'e2e_helpers.dart';

/// What happens to a patch on an install.
enum Outcome {
  /// The app runs the patch.
  applied,

  /// The updater logs a bad or missing signature and the app keeps the code
  /// it ran before the patch.
  refused,

  /// Should be refused, but is applied: a known bug.
  xfail,
}

enum Mode {
  strict('strict'),
  installOnly('install_only');

  const Mode(this.label);
  final String label;
}

/// Flutter versions whose engine skips the signature check in install_only
/// (updater#352). The Flutter the CLI pins (null) has the fix (updater#396).
/// Measured on every supported version on 2026-10-24 (e2e run 40096125987).
const installOnlySkipsSignatureCheck = {'3.47.5', '3.44.9', '3.41.9'};

/// What [patch] should do on an install in [mode] built with [flutter].
Outcome expected(String patch, Mode mode, String? flutter) {
  if (patch == 'managed' || patch == 'valid') return Outcome.applied;
  if (mode == Mode.installOnly &&
      installOnlySkipsSignatureCheck.contains(flutter)) {
    return Outcome.xfail;
  }
  return Outcome.refused;
}

Future<void> main(List<String> args) async {
  final target = switch (args.firstOrNull) {
    'linux' => LinuxTarget(),
    'macos' => MacosTarget(),
    'windows' => WindowsTarget(),
    'android' => AndroidTarget(),
    _ => null,
  };
  if (target == null || args.length > 2) {
    print(
      'Usage: dart scripts/patch_signing_e2e.dart '
      '<linux|macos|windows|android> '
      '[<flutter-version>]',
    );
    exit(64);
  }
  final flutter = args.length == 2 ? args[1] : null;
  final work = Directory.systemTemp.createTempSync('shorebird_signing_');
  await target.setUp();
  await runE2e(
    title:
        'Patch signing on ${target.title}, '
        'Flutter ${flutter ?? 'pinned by the CLI'}',
    columns: ['Case', 'Expected', 'Actual', 'Result', 'Time'],
    body: () => run(target, work, flutter),
    tearDown: target.tearDown,
  );
}

/// Makes the app, its releases and patches, and checks each install.
Future<void> run(Target target, Directory work, String? flutter) async {
  final flutterArgs = [if (flutter != null) '--flutter-version=$flutter'];
  const patchArgs = ['--allow-asset-diffs', '--allow-native-diffs', '-v'];
  String key(String name) => '${work.path}/$name';

  for (final name in ['key_a', 'key_b']) {
    await sh(work, 'openssl', ['genrsa', '-out', key('$name.pem'), '2048']);
    await sh(work, 'openssl', [
      'rsa',
      '-in',
      key('$name.pem'),
      '-pubout',
      '-out',
      key('$name.pub.pem'),
    ]);
  }

  final app = await createApp(work, target.name, version: '1.0.0+1');

  // Release 1.0.0+1 with the customer's key A.
  await timed(
    'release_customer',
    () => sh(app, 'shorebird', [
      'release',
      target.name,
      ...target.releaseArgs,
      ...flutterArgs,
      '--public-key-path=${key('key_a.pub.pem')}',
      '-v',
    ]),
  );
  final customer = await target.installs(work, app, 'customer');

  final customerPatches = {
    'wrong_key': [
      '--public-key-path=${key('key_b.pub.pem')}',
      '--private-key-path=${key('key_b.pem')}',
    ],
    'unsigned': <String>[],
    'valid': [
      '--public-key-path=${key('key_a.pub.pem')}',
      '--private-key-path=${key('key_a.pem')}',
    ],
  };
  for (final MapEntry(key: patch, value: signingArgs)
      in customerPatches.entries) {
    setLabel(app, patch);
    await timed(
      'patch_$patch',
      () => sh(app, 'shorebird', [
        'patch',
        target.name,
        '--release-version=1.0.0+1',
        ...patchArgs,
        ...signingArgs,
      ]),
    );
    for (final install in customer) {
      await check(patch, install, flutter);
    }
  }

  // Release 1.0.0+2 with the default: a Shorebird-managed key.
  setLabel(app, 'release');
  setVersion(app, '1.0.0+2');
  await timed(
    'release_managed',
    () => sh(app, 'shorebird', [
      'release',
      target.name,
      ...target.releaseArgs,
      ...flutterArgs,
      '-v',
    ]),
  );
  if (!(await target.builtShorebirdYaml(app)).contains('patch_public_key')) {
    throw Exception('The managed release embedded no public key.');
  }
  final managed = await target.installs(work, app, 'managed');

  setLabel(app, 'managed');
  await timed(
    'patch_managed',
    () => sh(app, 'shorebird', [
      'patch',
      target.name,
      '--release-version=1.0.0+2',
      ...patchArgs,
    ]),
  );
  for (final install in managed) {
    await check('managed', install, flutter);
  }
}

/// A platform this test runs on: how to build, install and launch the app.
abstract class Target {
  /// The name `flutter create`, `shorebird release` and `shorebird patch`
  /// take.
  String get name;

  /// The name in the report.
  String get title;

  List<String> get releaseArgs => const [];

  Future<void> setUp() async {}

  Future<void> tearDown() async {}

  /// The generated (bundled) shorebird.yaml in the release just built.
  Future<String> builtShorebirdYaml(Directory app);

  /// Installs the release just built, once per mode this platform checks.
  Future<List<Install>> installs(Directory work, Directory app, String release);
}

/// A release installed in one [mode], with its own updater state.
abstract class Install {
  Mode get mode;

  /// Launches the app and returns once a line of its output matches [until]
  /// (true), or it exits or [timeout] passes (false), with its output. The
  /// app is stopped before this returns.
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  });
}

/// Writes `patch_verification: install_only` into [shorebirdYaml], a
/// generated (bundled) shorebird.yaml: what the
/// CLI writes when it builds with this setting. The CLI refuses to build it on
/// engines that skip the check (#4163), but releases made before that are on
/// devices.
void setInstallOnly(File shorebirdYaml) {
  shorebirdYaml.writeAsStringSync(
    '\npatch_verification: install_only\n',
    mode: FileMode.append,
  );
}

class LinuxTarget extends Target {
  Process? _xvfb;

  @override
  String get name => 'linux';

  @override
  String get title => 'Linux';

  @override
  Future<void> setUp() async => _xvfb = await startXvfb();

  @override
  Future<void> tearDown() async => _xvfb?.kill();

  Directory bundle(Directory app) =>
      Directory('${app.path}/build/linux/x64/release/bundle');

  @override
  Future<String> builtShorebirdYaml(Directory app) async => File(
    '${bundle(app).path}/data/flutter_assets/shorebird.yaml',
  ).readAsStringSync();

  /// Copies the release to a strict and an install_only install, each with
  /// its own HOME, where the updater keeps its state.
  @override
  Future<List<Install>> installs(
    Directory work,
    Directory app,
    String release,
  ) async {
    return [
      for (final mode in Mode.values)
        () {
          final dir = '${work.path}/${release}_${mode.label}';
          final copy = Process.runSync('cp', ['-r', bundle(app).path, dir]);
          if (copy.exitCode != 0) throw Exception('cp failed: ${copy.stderr}');
          if (mode == Mode.installOnly) {
            setInstallOnly(File('$dir/data/flutter_assets/shorebird.yaml'));
          }
          return LinuxInstall(
            Directory(dir),
            Directory('${dir}_home')..createSync(),
            mode,
          );
        }(),
    ];
  }
}

class LinuxInstall extends Install {
  LinuxInstall(this.bundle, this.home, this.mode);
  final Directory bundle;
  final Directory home;
  @override
  final Mode mode;

  @override
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  }) => launchLinux(bundle, home, until: until, timeout: timeout);
}

class MacosTarget extends Target {
  static const bundleIdBase = 'com.example.signing-e2e';
  final _bundleIds = <String>[];

  /// Each install's sandbox container, which holds its updater state.
  static Directory containerData(String bundleId) => Directory(
    '${Platform.environment['HOME']}/Library/Containers/$bundleId/Data/Library',
  );

  /// Empties [bundleId]'s container. macOS doesn't let us delete a container
  /// itself, only its contents.
  static void clearContainer(String bundleId) {
    final library = containerData(bundleId);
    if (library.existsSync()) library.deleteSync(recursive: true);
  }

  @override
  String get name => 'macos';

  @override
  String get title => 'macOS';

  Directory builtApp(Directory app) =>
      Directory('${app.path}/build/macos/Build/Products/Release/e2e_test.app');

  static String shorebirdYamlIn(String appPath) =>
      '$appPath/Contents/Frameworks/App.framework/Resources/flutter_assets/'
      'shorebird.yaml';

  @override
  Future<String> builtShorebirdYaml(Directory app) async =>
      File(shorebirdYamlIn(builtApp(app).path)).readAsStringSync();

  /// Copies the release to a strict and an install_only install. The sandbox
  /// keeps the updater's state in a container per bundle id, so each copy
  /// gets its own and is re-signed. Neither touches the Dart snapshot in
  /// App.framework/App that patches are diffed against.
  @override
  Future<List<Install>> installs(
    Directory work,
    Directory app,
    String release,
  ) async {
    final result = <Install>[];
    for (final mode in Mode.values) {
      final path = '${work.path}/${release}_${mode.label}.app';
      // Bundle ids allow only letters, digits, hyphens and periods.
      final bundleId = '$bundleIdBase.$release-${mode.label}'.replaceAll(
        '_',
        '-',
      );
      _bundleIds.add(bundleId);
      // An earlier run's state would carry over.
      clearContainer(bundleId);
      await sh(work, 'ditto', [builtApp(app).path, path]);
      await sh(work, '/usr/libexec/PlistBuddy', [
        '-c',
        'Set CFBundleIdentifier $bundleId',
        '$path/Contents/Info.plist',
      ]);
      const sign = [
        '--force',
        '--preserve-metadata=entitlements',
        '--timestamp=none',
        '-s',
        '-',
      ];
      if (mode == Mode.installOnly) {
        setInstallOnly(File(shorebirdYamlIn(path)));
        await sh(work, 'codesign', [
          ...sign,
          '$path/Contents/Frameworks/App.framework',
        ]);
      }
      await sh(work, 'codesign', [...sign, path]);
      result.add(MacosInstall(path, mode));
    }
    return result;
  }

  @override
  Future<void> tearDown() async => _bundleIds.forEach(clearContainer);
}

class MacosInstall extends Install {
  MacosInstall(this.path, this.mode);
  final String path;
  @override
  final Mode mode;

  @override
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  }) async {
    final process = await Process.start(
      '$path/Contents/MacOS/e2e_test',
      [],
      // The updater logs only to the unified log; this also writes those
      // lines to stderr.
      environment: {'OS_ACTIVITY_DT_MODE': '1'},
    );
    return watch(process, until: until, timeout: timeout);
  }
}

class WindowsTarget extends Target {
  @override
  String get name => 'windows';

  @override
  String get title => 'Windows';

  Directory runner(Directory app) =>
      Directory('${app.path}/build/windows/x64/runner/Release');

  @override
  Future<String> builtShorebirdYaml(Directory app) async => File(
    '${runner(app).path}/data/flutter_assets/shorebird.yaml',
  ).readAsStringSync();

  /// The updater's state, which the engine keeps directly in %LOCALAPPDATA%
  /// for every app, so a stale patch from an earlier run would boot.
  static const stateEntries = [
    'state.json',
    'pointers.json',
    // Older engines' state file.
    'patches_state.json',
    'patches',
    'downloads',
  ];

  @override
  Future<void> setUp() async {
    if (Platform.environment['CI'] == null) {
      throw Exception(
        'On Windows this deletes ${stateEntries.join(', ')} from '
        '%LOCALAPPDATA%, shared by every Shorebird app (and maybe other '
        'programs), so it runs only where CI is set.',
      );
    }
  }

  /// Copies the release to one install, after deleting the updater's state.
  /// Nothing per process redirects %LOCALAPPDATA%, so a second install would
  /// share the first one's state.
  @override
  Future<List<Install>> installs(
    Directory work,
    Directory app,
    String release,
  ) async {
    final state = Platform.environment['LOCALAPPDATA']!;
    for (final name in stateEntries) {
      final entry = FileSystemEntity.typeSync('$state/$name');
      if (entry == FileSystemEntityType.directory) {
        Directory('$state/$name').deleteSync(recursive: true);
      } else if (entry == FileSystemEntityType.file) {
        File('$state/$name').deleteSync();
      }
    }
    final dir = Directory('${work.path}/${release}_${Mode.strict.label}');
    copyDirectory(runner(app), dir);
    return [WindowsInstall(dir)];
  }
}

class WindowsInstall extends Install {
  WindowsInstall(this.dir);
  final Directory dir;

  @override
  Mode get mode => Mode.strict;

  @override
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  }) async {
    final process = await Process.start('${dir.path}/e2e_test.exe', []);
    return watch(process, until: until, timeout: timeout);
  }
}

/// Copies [from] and everything in it to [to].
void copyDirectory(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entity is Directory) {
      copyDirectory(entity, Directory('${to.path}/$name'));
    } else if (entity is File) {
      entity.copySync('${to.path}/$name');
    }
  }
}

class AndroidTarget extends Target {
  static const package = 'com.example.e2e_test.e2e_test';

  @override
  String get name => 'android';

  @override
  String get title => 'Android';

  @override
  List<String> get releaseArgs => const ['--artifact=apk'];

  File apk(Directory app) =>
      File('${app.path}/build/app/outputs/flutter-apk/app-release.apk');

  @override
  Future<String> builtShorebirdYaml(Directory app) async {
    final result = await Process.run('unzip', [
      '-p',
      apk(app).path,
      'assets/flutter_assets/shorebird.yaml',
    ]);
    if (result.exitCode != 0) throw Exception('unzip: ${result.stderr}');
    return result.stdout as String;
  }

  /// Installs the release in place of any earlier one, clearing the
  /// updater's state.
  @override
  Future<List<Install>> installs(
    Directory work,
    Directory app,
    String release,
  ) async {
    // Fails when it isn't installed.
    await Process.run('adb', ['uninstall', package]);
    await sh(work, 'adb', ['install', apk(app).path]);
    return [AndroidInstall()];
  }
}

class AndroidInstall extends Install {
  @override
  Mode get mode => Mode.strict;

  @override
  Future<(bool, String)> launch({
    required RegExp until,
    required Duration timeout,
  }) async {
    final pid = await startAndroidApp(AndroidTarget.package);
    if (pid == null) return (false, 'The app exited right after it started.');
    // This launch's lines, from its start, and none of an earlier launch's. A
    // native crash's "Fatal signal" line is the app's too.
    final logcat = await Process.start('adb', ['logcat', '--pid=$pid']);
    try {
      return await watch(logcat, until: until, timeout: timeout);
    } finally {
      await stopAndroidApp(AndroidTarget.package);
    }
  }
}

/// Launches [install] twice after [patch] was published (once to download
/// and install it, once to boot) and records whether it ran the patch.
Future<void> check(String patch, Install install, String? flutter) async {
  final name = '${patch}_${install.mode.label}';
  final stopwatch = Stopwatch()..start();
  final (:updateLog, :bootLog, label: running) = await updateAndBoot(
    name,
    install.launch,
  );
  final String actual;
  if (running == patch) {
    actual = 'applied';
  } else if (RegExp(
    'Patch signature is (invalid|missing)',
  ).hasMatch(updateLog + bootLog)) {
    actual = 'refused';
  } else {
    // Not running the patch proves nothing unless the updater refused it for
    // its signature: the patch may never have been served.
    actual = 'not run, with no signature failure logged';
  }

  final want = expected(patch, install.mode, flutter);
  final String verdict;
  switch ((want, actual)) {
    case (Outcome.applied, 'applied') || (Outcome.refused, 'refused'):
      verdict = 'PASS';
    case (Outcome.xfail, 'applied'):
      verdict = 'XFAIL (known bug: should be refused)';
    case (Outcome.xfail, 'refused'):
      verdict = 'XPASS: now refused; update installOnlySkipsSignatureCheck';
      failed = true;
    default:
      verdict = 'FAIL';
      failed = true;
  }
  results.add(
    '| $name | ${want.name} | $actual (runs $running) | $verdict '
    '| ${stopwatch.elapsed.inSeconds}s |',
  );
  print('$name: expected ${want.name}, $actual (runs $running): $verdict');
  if (verdict == 'FAIL' || verdict.startsWith('XPASS')) {
    print('--- update launch log\n$updateLog\n--- boot launch log\n$bootLog');
  }
}
