// cspell:words genkey keyalg keysize storepass keypass dname getprop avds
// cspell:words avdmanager
// ignore_for_file: avoid_print

// End-to-end test of release, patch and boot on Android: the real CLI against
// a real server, a real Flutter build, and the app run on a device. It creates
// an empty app, releases it, checks the release prints "hello world", patches
// it to print "hello shorebird", checks the patch downloads, then cold-starts
// the app and checks it runs the patch.
//
// Usage: dart scripts/patch_e2e.dart [--cli <path|version>] [--avd <name>]
//            [--org-id <id>] [<flutter-version>|default]
//
//   <flutter-version>  Flutter version to release with. "default" (or
//                      nothing) uses the Flutter the CLI pins. The app is
//                      created with the `flutter` on PATH, so use one whose
//                      templates that version builds (CI installs the same
//                      version).
//   --cli <path>       Shorebird checkout to test (the directory holding
//                      bin/shorebird). Defaults to this checkout.
//   --cli <version>    A released CLI, e.g. 1.4.0. Its tag is cloned once into
//                      $XDG_CACHE_HOME (or ~/.cache)/shorebird_patch_e2e/ and
//                      reused. Its app is created with its pinned Flutter.
//   --avd <name>       AVD to boot when no device is attached. Defaults to
//                      $SHOREBIRD_E2E_AVD, else the first `emulator
//                      -list-avds` prints.
//   --org-id <id>      Organization to create the app in. Defaults to
//                      $SHOREBIRD_E2E_ORG_ID; needed when the account can
//                      create apps in more than one (Shorebird E2E is 437 on
//                      dev).
//
// Device: an attached device or running emulator is used as is (set
// ANDROID_SERIAL to pick one of several). With none attached, it boots the AVD
// headless, as emulator-5580 or on the port ANDROID_SERIAL=emulator-<port>
// names, waits for it to finish booting, and shuts it down at the end.
//
// Server: $SHOREBIRD_HOSTED_URL, default https://api-dev.shorebird.dev. The
// app made there is deleted at the end, pass or fail.
//
// Prerequisites: Flutter, the Android SDK with adb on PATH, Java, and a
// signed-in Shorebird account (CI signs in with OIDC). `shorebird init` and
// the cleanup run with this checkout's CLI, which migrates and deletes the
// login file older CLIs read, so for --cli <version> set SHOREBIRD_TOKEN, from
// `shorebird login:ci` run with that version.
//
// Examples:
//   dart scripts/patch_e2e.dart               # this CLI, its pinned Flutter
//   dart scripts/patch_e2e.dart 3.27.4        # release with Flutter 3.27.4
//   dart scripts/patch_e2e.dart --cli 1.4.0   # CLI 1.4.0, current server

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How long to wait for a device to boot, or for an expected log line.
const waitTimeout = Duration(minutes: 5);

const package = 'com.example.e2e_test.e2e_test';
const releaseVersion = '0.1.0+1';

/// This checkout: the default CLI under test, and the one that runs `init`
/// and the cleanup, since an older CLI under test may lack `--org-id` and
/// `api`.
final repoRoot = File(Platform.script.toFilePath()).parent.parent.path;
final repoShorebird = '$repoRoot/bin/shorebird';

final hostedUrl =
    Platform.environment['SHOREBIRD_HOSTED_URL'] ??
    'https://api-dev.shorebird.dev';

/// The environment every command runs with. The CLI reads
/// SHOREBIRD_HOSTED_URL (see ShorebirdEnv.hostedUri); adb reads
/// ANDROID_SERIAL, set when this script boots its own emulator.
final env = {'SHOREBIRD_HOSTED_URL': hostedUrl};

/// The app this run made, to delete at the end.
String? appId;

/// The emulator this run started, to shut down at the end.
Process? emulator;

/// This run's workspace, holding the app and its builds, to delete at the
/// end.
Directory? workspace;

Future<void> main(List<String> args) async {
  final options = Options.parse(args);
  Future<void> cleanUp() async {
    final id = appId;
    appId = null;
    if (id != null) {
      // `shorebird init` mints a new app on every run, and the nightly runs
      // one per Flutter version. Left alone the e2e account's app list grows
      // without bound, and every `shorebird release` fetches the whole list:
      // by Aug 2026 it was a 7.7MB response that saturated api-dev. Delete
      // the app, pass or fail, so the list stays flat.
      print('Deleting e2e app $id');
      final result = await Process.run(repoShorebird, [
        'api',
        '-X',
        'DELETE',
        'apps/$id',
      ], environment: env);
      if (result.exitCode != 0) {
        print('⚠️  Failed to delete e2e app $id; it will need pruning.');
      }
    }
    await stopEmulator();
    workspace?.deleteSync(recursive: true);
    workspace = null;
  }

  // A cancelled or timed-out job is signaled, which skips `finally`.
  final signals = [
    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm])
      signal.watch().listen((_) async {
        await cleanUp();
        exit(1);
      }),
  ];
  try {
    await run(options);
    print('✅ All tests passed!');
  } on Failure catch (failure) {
    print('❌ $failure');
    exitCode = 1;
  } finally {
    await cleanUp();
    // Watching a signal keeps the process alive.
    for (final subscription in signals) {
      await subscription.cancel();
    }
  }
}

class Options {
  Options({
    required this.flutterVersion,
    required this.cli,
    required this.avd,
    required this.orgId,
  });

  factory Options.parse(List<String> args) {
    String? flutterVersion;
    String? cli;
    var avd = Platform.environment['SHOREBIRD_E2E_AVD'];
    var orgId = Platform.environment['SHOREBIRD_E2E_ORG_ID'];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg.startsWith('-')) {
        if (!const {'--cli', '--avd', '--org-id'}.contains(arg)) {
          usageError('Unknown option $arg.');
        }
        if (i + 1 == args.length) usageError('$arg needs a value.');
        final value = args[++i];
        switch (arg) {
          case '--cli':
            cli = value;
          case '--avd':
            avd = value;
          case '--org-id':
            orgId = value;
        }
      } else {
        flutterVersion = arg == 'default' ? null : arg;
      }
    }
    return Options(
      flutterVersion: flutterVersion,
      cli: cli,
      avd: avd == null || avd.isEmpty ? null : avd,
      orgId: orgId == null || orgId.isEmpty ? null : orgId,
    );
  }

  /// null is the Flutter the CLI pins.
  final String? flutterVersion;

  /// A checkout path or a released version; null is this checkout.
  final String? cli;
  final String? avd;
  final String? orgId;
}

Never usageError(String message) {
  print('❌ $message See the usage at the top of scripts/patch_e2e.dart.');
  exit(64);
}

/// A step that failed, with what to look at.
class Failure implements Exception {
  Failure(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<void> run(Options options) async {
  final cliDir = await resolveCli(options.cli);
  final shorebird = '$cliDir/bin/shorebird';
  await sh(shorebird, ['--version']);

  if (!await hasDevice()) await startEmulator(options.avd);

  // Intentionally including a space in the path.
  final work = workspace = Directory.systemTemp.createTempSync(
    'shorebird workspace-',
  );

  // A released CLI's pinned Flutter may not build the templates a newer host
  // Flutter writes, so create its app with that Flutter, which
  // `shorebird --version` installed.
  var createFlutter = 'flutter';
  if (options.flutterVersion == null && cliDir != repoRoot) {
    final revision = File(
      '$cliDir/bin/internal/flutter.version',
    ).readAsStringSync().trim();
    final pinned = '$cliDir/bin/cache/flutter/$revision/bin/flutter';
    if (File(pinned).existsSync()) createFlutter = pinned;
  }
  await sh(createFlutter, [
    'create',
    'e2e_test',
    '--org',
    'com.example.e2e_test',
    '--empty',
    '--platforms',
    'android',
  ], dir: work);
  final app = Directory('${work.path}/e2e_test');
  setMessage(app, 'hello world');

  await sh(repoShorebird, [
    'init',
    '--force',
    if (options.orgId != null) '--org-id=${options.orgId}',
    '-v',
  ], dir: app);
  final shorebirdYaml = File('${app.path}/shorebird.yaml');
  appId = RegExp(
    r'app_id: (\S+)',
  ).firstMatch(shorebirdYaml.readAsStringSync())!.group(1);
  shorebirdYaml.writeAsStringSync(
    'base_url: $hostedUrl\n',
    mode: FileMode.append,
  );

  await sh('flutter', ['doctor', '--verbose'], dir: app);
  await sh(shorebird, ['doctor', '--verbose'], dir: app);

  // Android Studio creates this keystore; CI has to. bundletool signs the
  // preview's APKs with it.
  final home = Platform.environment['HOME']!;
  if (!File('$home/.android/debug.keystore').existsSync()) {
    Directory('$home/.android').createSync(recursive: true);
    await sh('keytool', [
      '-genkey',
      '-v',
      '-keystore',
      '$home/.android/debug.keystore',
      '-keyalg',
      'RSA',
      '-keysize',
      '2048',
      '-validity',
      '10000',
      '-alias',
      'AndroidDebugKey',
      '-storepass',
      'android',
      '-keypass',
      'android',
      '-dname',
      'CN=Android Debug,O=Android,C=US',
    ]);
  }

  // CLIs before --split-debug-info became a `shorebird` option (e.g. 1.4.0)
  // take it as a flag forwarded to `flutter build`.
  final releaseHelp = await Process.run(shorebird, [
    'release',
    '--help',
  ], environment: env);
  final splitDebugInfo = [
    if (!RegExp(
      '^ +--split-debug-info',
      multiLine: true,
    ).hasMatch('${releaseHelp.stdout}'))
      '--',
    '--split-debug-info=./build/symbols',
  ];

  await sh(shorebird, [
    'release',
    'android',
    if (options.flutterVersion != null)
      '--flutter-version=${options.flutterVersion}',
    '-v',
    ...splitDebugInfo,
  ], dir: app);

  final preview = [
    'preview',
    '--release-version',
    releaseVersion,
    '--app-id',
    appId!,
    '--platform',
    'android',
    // Set when this script booted its own emulator, or by the caller.
    if (env['ANDROID_SERIAL'] ?? Platform.environment['ANDROID_SERIAL']
        case final serial? when serial.isNotEmpty) ...[
      '--device-id',
      serial,
    ],
    '-v',
  ];
  await waitForLine('I flutter : hello world', shorebird, preview, dir: app);
  print("✅ 'hello world' was printed");

  setMessage(app, 'hello shorebird');
  await sh(shorebird, [
    'patch',
    'android',
    '--release-version',
    releaseVersion,
    '-v',
    ...splitDebugInfo,
  ], dir: app);

  // The preview reinstalls the release, which downloads and installs the
  // patch.
  await waitForLine('Patch 1 successfully', shorebird, preview, dir: app);
  print('✅ Patch 1 successfully installed');

  // Cold-start the app, *not* with `shorebird preview`, which reinstalls the
  // release. The log tail starts at the device's clock just before launch, so
  // it can't match a line an earlier run on this device printed.
  await adb(['shell', 'am', 'force-stop', package]);
  final launchedAt = (await adb(['shell', 'date', '+%s'])).trim();
  await adb([
    'shell',
    'monkey',
    '-p',
    package,
    '-c',
    'android.intent.category.LAUNCHER',
    '1',
  ]);
  await waitForLine('I flutter : hello shorebird', 'adb', [
    'logcat',
    '-T',
    '$launchedAt.000',
  ]);
  print("✅ 'hello shorebird' was printed");
}

void setMessage(Directory app, String message) {
  File(
    '${app.path}/lib/main.dart',
  ).writeAsStringSync("void main() { print('$message'); }\n");
}

/// Resolves --cli to a checkout: a path is used as is, a version is cloned at
/// its tag once and reused.
Future<String> resolveCli(String? cli) async {
  final String dir;
  if (cli == null) {
    dir = repoRoot;
  } else if (Directory(cli).existsSync()) {
    dir = Directory(cli).absolute.path;
  } else if (RegExp(r'^v?\d+\.\d+\.\d+$').hasMatch(cli)) {
    final tag = cli.startsWith('v') ? cli : 'v$cli';
    final cache =
        Platform.environment['XDG_CACHE_HOME'] ??
        '${Platform.environment['HOME']}/.cache';
    dir = '$cache/shorebird_patch_e2e/cli-$tag';
    if (!Directory(dir).existsSync()) {
      final tmp = Directory('$dir.tmp');
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      await sh('git', [
        'clone',
        '--depth',
        '1',
        '--branch',
        tag,
        'https://github.com/shorebirdtech/shorebird.git',
        tmp.path,
      ]);
      // Installs track the stable branch, and older CLIs read their version
      // and check for updates through it, failing on a detached HEAD or a
      // branch without an upstream.
      for (final gitArgs in [
        ['remote', 'set-branches', 'origin', 'stable'],
        ['fetch', '--depth', '1', 'origin', 'stable'],
        ['checkout', '-b', 'stable', '--no-track'],
        ['branch', '--set-upstream-to=origin/stable'],
      ]) {
        await sh('git', ['-C', tmp.path, ...gitArgs]);
      }
      tmp.renameSync(dir);
    }
  } else {
    usageError('--cli $cli is neither a directory nor a version like 1.4.0.');
  }
  if (!File('$dir/bin/shorebird').existsSync()) {
    usageError('$dir has no bin/shorebird; --cli takes a Shorebird checkout.');
  }
  return dir;
}

Future<bool> hasDevice() async {
  // A cold adb server can list a running emulator as offline at first.
  await adb(['start-server']);
  final serial = Platform.environment['ANDROID_SERIAL'];
  if (serial != null && serial.isNotEmpty) {
    final state = await Process.run('adb', ['-s', serial, 'get-state']);
    return '${state.stdout}'.trim() == 'device';
  }
  final devices = await adb(['devices']);
  return RegExp(r'\tdevice$', multiLine: true).hasMatch(devices);
}

/// Boots [requestedAvd] (or the first AVD) headless on a port of our own, so
/// its serial is known and every later adb command goes to it.
Future<void> startEmulator(String? requestedAvd) async {
  final sdk =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'] ??
      '${Platform.environment['HOME']}/Library/Android/sdk';
  final emulatorPath = '$sdk/emulator/emulator';
  if (!File(emulatorPath).existsSync()) {
    throw Failure(
      'No device is attached and there is no emulator at $emulatorPath. '
      'Attach a device, or set ANDROID_HOME to an SDK with the emulator.',
    );
  }
  final avd =
      requestedAvd ??
      LineSplitter.split(
        '${(await Process.run(emulatorPath, ['-list-avds'])).stdout}',
      ).firstOrNull;
  if (avd == null) {
    throw Failure(
      'No device is attached and there are no AVDs to boot. Create one in '
      'Android Studio or with avdmanager, or attach a device.',
    );
  }
  var port = '5580';
  final serial = Platform.environment['ANDROID_SERIAL'] ?? '';
  if (serial.isNotEmpty) {
    final match = RegExp(r'^emulator-(\d+)$').firstMatch(serial);
    if (match == null) throw Failure('ANDROID_SERIAL=$serial is not attached.');
    port = match.group(1)!;
  }
  env['ANDROID_SERIAL'] = 'emulator-$port';
  print('No device attached; booting AVD $avd as emulator-$port.');
  final process = emulator = await Process.start(emulatorPath, [
    '-avd',
    avd,
    '-port',
    port,
    '-no-window',
    '-no-audio',
    '-no-boot-anim',
    '-no-snapshot-save',
  ]);
  final log = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(log.write);
  process.stderr.transform(utf8.decoder).listen(log.write);
  var exited = false;
  unawaited(process.exitCode.then((_) => exited = true));

  // `adb wait-for-device` returns as soon as adb sees the device, well before
  // the package manager can install anything.
  final deadline = DateTime.now().add(waitTimeout);
  while (true) {
    final booted = await Process.run('adb', [
      'shell',
      'getprop',
      'sys.boot_completed',
    ], environment: env);
    if ('${booted.stdout}'.trim() == '1') return;
    if (exited) throw Failure('The emulator exited while booting:\n$log');
    if (DateTime.now().isAfter(deadline)) {
      throw Failure("The emulator didn't finish booting within $waitTimeout.");
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

Future<void> stopEmulator() async {
  final process = emulator;
  emulator = null;
  if (process == null) return;
  print('Shutting down the emulator this script started');
  await Process.run('adb', ['emu', 'kill'], environment: env);
  await process.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
}

/// Runs adb on the device under test; throws if it fails. Returns its
/// output.
Future<String> adb(List<String> args) async {
  final result = await Process.run('adb', args, environment: env);
  if (result.exitCode != 0) {
    throw Failure(
      'adb ${args.join(' ')} exited with ${result.exitCode}: ${result.stderr}',
    );
  }
  return '${result.stdout}';
}

/// Runs [executable], showing its output; throws if it fails.
Future<void> sh(String executable, List<String> args, {Directory? dir}) async {
  print('+ $executable ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: dir?.path,
    environment: env,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw Failure('$executable ${args.join(' ')} exited with $code.');
  }
}

/// Runs [executable], showing its output, until a line contains [pattern],
/// then stops it. Fails with the device log if the output ends first or
/// [waitTimeout] passes.
Future<void> waitForLine(
  String pattern,
  String executable,
  List<String> args, {
  Directory? dir,
}) async {
  print('+ $executable ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: dir?.path,
    environment: env,
  );
  final matched = Completer<bool>();
  void onLine(String line) {
    print(line);
    if (!matched.isCompleted && line.contains(pattern)) matched.complete(true);
  }

  // adb logcat sometimes lets through bytes that aren't UTF-8.
  const decoder = Utf8Decoder(allowMalformed: true);
  final streams = [
    for (final stream in [process.stdout, process.stderr])
      stream.transform(decoder).transform(const LineSplitter()).listen(onLine),
  ];
  // Not on exit: lines printed just before it may still be arriving.
  unawaited(
    Future.wait([for (final s in streams) s.asFuture<void>()]).then((_) {
      if (!matched.isCompleted) matched.complete(false);
    }),
  );
  final found = await matched.future.timeout(
    waitTimeout,
    onTimeout: () => false,
  );
  // `shorebird preview` tails `adb logcat`, which would outlive it.
  await Process.run('pkill', ['-P', '${process.pid}']);
  process.kill();
  for (final stream in streams) {
    await stream.cancel();
  }
  if (!found) {
    final log = await Process.run('adb', [
      'logcat',
      '-d',
      '-b',
      'all',
    ], environment: env);
    throw Failure(
      "'$pattern' wasn't printed: `$executable ${args.join(' ')}` ended, or "
      'ran past $waitTimeout. Device log (all buffers):\n${log.stdout}',
    );
  }
}
