// cspell:words genrsa pubout Xvfb xfail XPASS logcat libexec
// ignore_for_file: avoid_print

// End-to-end test of patch signing: the real CLI against a real server, a
// real Flutter build, and the built app launched, checking which code it runs
// after it downloads each patch. Runs on Linux (the app headless under Xvfb),
// macOS, and Android (on the one emulator or device adb sees).
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
// device holds one install of an app, so Android checks strict only;
// install_only is the updater's own logic, the same on every platform. Each
// patch prints its own label, so after each patch every install is launched
// twice (download and install, then boot), and the label it prints says
// whether it ran the patch. Each install keeps its own updater state, so a
// refused patch stays marked bad, as on a device.
//
// Set SHOREBIRD_ORG_ID to choose the organization for the app when the
// account can create apps in more than one.
//
// Prerequisites: Shorebird on PATH and signed in (CI signs in with OIDC),
// openssl, and per platform: on Linux the Flutter Linux build dependencies and
// Xvfb; on macOS Xcode; for Android the Android SDK and a running emulator.
//
// Usage: dart scripts/patch_signing_e2e.dart <linux|macos|android>
//     [<flutter-version>]
// Without a version it uses the Flutter the CLI pins.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
/// (updater#352, until the fix ships). null is the Flutter the CLI pins.
/// Measured on every supported version on 2026-10-24 (e2e run 40096125987).
const installOnlySkipsSignatureCheck = {null, '3.47.5', '3.44.9', '3.41.9'};

/// What [patch] should do on an install in [mode] built with [flutter].
Outcome expected(String patch, Mode mode, String? flutter) {
  if (patch == 'managed' || patch == 'valid') return Outcome.applied;
  if (mode == Mode.installOnly &&
      installOnlySkipsSignatureCheck.contains(flutter)) {
    return Outcome.xfail;
  }
  return Outcome.refused;
}

/// How long one launch may take to finish its update check, and to print its
/// label.
const updateTimeout = Duration(minutes: 3);
const bootTimeout = Duration(minutes: 1);

final results = <String>[];

/// The app this run made, to delete at the end.
String? runAppId;
final timings = <String>[];
bool failed = false;

/// Why the run stopped before checking every case, if it did.
String? stoppedEarly;

Future<void> main(List<String> args) async {
  final target = switch (args.firstOrNull) {
    'linux' => LinuxTarget(),
    'macos' => MacosTarget(),
    'android' => AndroidTarget(),
    _ => null,
  };
  if (target == null || args.length > 2) {
    print(
      'Usage: dart scripts/patch_signing_e2e.dart <linux|macos|android> '
      '[<flutter-version>]',
    );
    exit(64);
  }
  final flutter = args.length == 2 ? args[1] : null;
  final work = Directory.systemTemp.createTempSync('shorebird_signing_');
  await target.setUp();
  Future<void> cleanUp() async {
    report(target, flutter);
    final appId = runAppId;
    runAppId = null;
    if (appId != null) {
      // Each run mints an app; delete it so the e2e account's app list stays
      // flat (see patch_e2e.dart).
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
    await target.tearDown();
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
    await run(target, work, flutter);
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

  await timed(
    'create',
    () => sh(work, pinnedFlutter(), [
      'create',
      'e2e_test',
      '--org',
      'com.example.e2e_test',
      '--empty',
      '--platforms',
      target.name,
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
  runAppId = RegExp(
    r'app_id: (\S+)',
  ).firstMatch(shorebirdYaml.readAsStringSync())!.group(1);

  // Release 1.0.0+1 with the customer's key A.
  setVersion(app, '1.0.0+1');
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
  Future<void> setUp() async {
    _xvfb = await Process.start('Xvfb', [
      ':99',
      '-screen',
      '0',
      '1024x768x24',
    ], mode: ProcessStartMode.inheritStdio);
  }

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
  }) async {
    final process = await Process.start(
      '${bundle.path}/e2e_test',
      [],
      environment: {'HOME': home.path, 'DISPLAY': ':99'},
    );
    return watch(process, until: until, timeout: timeout);
  }
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
    // -W returns once the app is up, so it has a pid.
    await sh(Directory.current, 'adb', [
      'shell',
      'am',
      'start',
      '-W',
      '-n',
      '${AndroidTarget.package}/.MainActivity',
    ]);
    final pid = (await Process.run('adb', [
      'shell',
      'pidof',
      AndroidTarget.package,
    ])).stdout.toString().trim();
    if (pid.isEmpty) return (false, 'The app exited right after it started.');
    // This launch's lines, from its start, and none of an earlier launch's. A
    // native crash's "Fatal signal" line is the app's too.
    final logcat = await Process.start('adb', ['logcat', '--pid=$pid']);
    try {
      return await watch(logcat, until: until, timeout: timeout);
    } finally {
      await sh(Directory.current, 'adb', [
        'shell',
        'am',
        'force-stop',
        AndroidTarget.package,
      ]);
    }
  }
}

/// Launches [install] twice after [patch] was published (once to download
/// and install it, once to boot) and records whether it ran the patch.
Future<void> check(String patch, Install install, String? flutter) async {
  final name = '${patch}_${install.mode.label}';
  final stopwatch = Stopwatch()..start();
  final (updated, updateLog) = await install.launch(
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (!updated) {
    throw Exception(
      "$name: the update check didn't finish (exited, or ran past "
      '$updateTimeout). Its output:\n$updateLog',
    );
  }
  final (booted, bootLog) = await install.launch(
    until: RegExp('signing-e2e: '),
    timeout: bootTimeout,
  );
  if (!booted) {
    throw Exception(
      '$name: the app printed no label (exited, or ran past $bootTimeout). '
      'Its output:\n$bootLog',
    );
  }

  final running = RegExp(
    'signing-e2e: ([a-z_]+)',
  ).firstMatch(bootLog)!.group(1);
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
  ).writeAsStringSync("void main() { print('signing-e2e: $label'); }\n");
}

void setVersion(Directory app, String version) {
  final pubspec = File('${app.path}/pubspec.yaml');
  pubspec.writeAsStringSync(
    pubspec.readAsStringSync().replaceFirst(
      RegExp('^version: .*', multiLine: true),
      'version: $version',
    ),
  );
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
void report(Target target, String? flutter) {
  final version = flutter ?? 'pinned by the CLI';
  final text = [
    '### Patch signing on ${target.title}, Flutter $version',
    '',
    '| Case | Expected | Actual | Result | Time |',
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
