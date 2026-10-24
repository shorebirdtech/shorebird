// cspell:words genrsa pubout Xvfb xfail XPASS
// ignore_for_file: avoid_print

// End-to-end test of patch signing: the real CLI against a real server, a
// real Flutter build, and the built app launched, checking which code it runs
// after it downloads each patch. Linux only for now; the app is run headless
// under Xvfb.
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
// Each release is installed twice: strict (the signature is checked at every
// launch) and install_only (checked once, at install). Each patch prints its
// own label, so after each patch every install is launched twice (download
// and install, then boot), and the label it prints says whether it ran the
// patch. Each install keeps its updater state in its own HOME, so a refused
// patch stays marked bad, as on a device.
//
// Prerequisites: Linux with the Flutter Linux build dependencies, Xvfb and
// openssl; Shorebird on PATH and signed in (CI signs in with OIDC).
//
// Usage: dart scripts/patch_signing_e2e.dart [<flutter-version>]
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

enum Mode { strict, installOnly }

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

Future<void> main(List<String> args) async {
  final flutter = args.isEmpty ? null : args.single;
  final work = Directory.systemTemp.createTempSync('shorebird_signing_');
  final xvfb = await Process.start('Xvfb', [
    ':99',
    '-screen',
    '0',
    '1024x768x24',
  ]);
  try {
    await run(work, flutter);
  } finally {
    report(flutter);
    xvfb.kill();
    final appId = runAppId;
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
      if (result.exitCode != 0) print('⚠️  Failed to delete e2e app $appId.');
    }
  }
  if (failed) {
    print('❌ Results differ from what is expected.');
    exit(1);
  }
  print('✅ All results are as expected.');
}

/// Makes the app, its releases and patches, and checks each install.
Future<void> run(Directory work, String? flutter) async {
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

  // Release 1.0.0+1 with the customer's key A.
  setVersion(app, '1.0.0+1');
  await timed(
    'release_customer',
    () => sh(app, 'shorebird', [
      'release',
      'linux',
      ...flutterArgs,
      '--public-key-path=${key('key_a.pub.pem')}',
      '-v',
    ]),
  );
  final customer = installs(work, app, 'customer');

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
        'linux',
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
    () => sh(app, 'shorebird', ['release', 'linux', ...flutterArgs, '-v']),
  );
  if (!File(
    '${bundle(app).path}/data/flutter_assets/shorebird.yaml',
  ).readAsStringSync().contains('patch_public_key')) {
    throw Exception('The managed release embedded no public key.');
  }
  final managed = installs(work, app, 'managed');

  setLabel(app, 'managed');
  await timed(
    'patch_managed',
    () => sh(app, 'shorebird', [
      'patch',
      'linux',
      '--release-version=1.0.0+2',
      ...patchArgs,
    ]),
  );
  for (final install in managed) {
    await check('managed', install, flutter);
  }
}

/// A copy of a release's build, with its own updater state.
class Install {
  Install(this.bundle, this.home, this.mode);
  final Directory bundle;
  final Directory home;
  final Mode mode;
}

Directory bundle(Directory app) =>
    Directory('${app.path}/build/linux/x64/release/bundle');

/// Copies the release just built to a strict and an install_only install.
List<Install> installs(Directory work, Directory app, String release) {
  return [
    for (final mode in Mode.values)
      () {
        final dir = '${work.path}/${release}_${mode.name}';
        Process.runSync('cp', ['-r', bundle(app).path, dir]);
        if (mode == Mode.installOnly) {
          // What the CLI writes when it builds with this setting. The CLI
          // refuses to build it on engines that skip the check (#4163), but
          // releases made before that are on devices.
          File('$dir/data/flutter_assets/shorebird.yaml').writeAsStringSync(
            '\npatch_verification: install_only\n',
            mode: FileMode.append,
          );
        }
        return Install(
          Directory(dir),
          Directory('${dir}_home')..createSync(),
          mode,
        );
      }(),
  ];
}

/// Launches [install] twice after [patch] was published (once to download
/// and install it, once to boot) and records whether it ran the patch.
Future<void> check(String patch, Install install, String? flutter) async {
  final name = '${patch}_${install.mode.name}';
  final stopwatch = Stopwatch()..start();
  final updateLog = await launch(
    install,
    until: RegExp('Update thread finished|Update failed'),
    timeout: updateTimeout,
  );
  if (updateLog == null) {
    throw Exception(
      "$name: the update check didn't finish within $updateTimeout.",
    );
  }
  final bootLog = await launch(
    install,
    until: RegExp('signing-e2e: '),
    timeout: bootTimeout,
  );
  if (bootLog == null) {
    throw Exception('$name: the app printed no label within $bootTimeout.');
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

/// Runs [install] until a line of its output matches [until] or [timeout]
/// passes, then stops it. Returns its output, or null if nothing matched.
Future<String?> launch(
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
  return found ? output.toString() : null;
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
void report(String? flutter) {
  final text = [
    '### Patch signing on Linux, Flutter ${flutter ?? 'pinned by the CLI'}',
    '',
    '| Case | Expected | Actual | Result | Time |',
    '| --- | --- | --- | --- | --- |',
    ...results,
    '',
    'Wall time by step: ${timings.join(', ')}',
  ].join('\n');
  print(text);
  final summary = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summary != null && summary.isNotEmpty) {
    File(summary).writeAsStringSync('$text\n', mode: FileMode.append);
  }
}
