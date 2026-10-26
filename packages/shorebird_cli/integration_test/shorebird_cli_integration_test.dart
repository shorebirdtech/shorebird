// cspell:words dartvm etime jcmd ppid safepoint taskkill tasklist
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/artifact_builder/shorebird_tracer.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

R runWithOverrides<R>(R Function() body) {
  return runScoped(
    body,
    values: {
      authRef,
      httpClientRef,
      loggerRef,
      // Auth signs in with GitHub Actions OIDC through this client.
      nonRetryingHttpClientRef,
      platformRef,
      shorebirdEnvRef,
      // TracingClient wraps the auth client and reads the ambient tracer on
      // every request, so any scope that issues HTTP has to seed it.
      shorebirdTracerRef,
    },
  );
}

void main() {
  final shorebirdHostedURL = Platform.environment['SHOREBIRD_HOSTED_URL'];
  if (shorebirdHostedURL == null || shorebirdHostedURL.isEmpty) {
    throw Exception('SHOREBIRD_HOSTED_URL environment variable is not set.');
  }
  final logger = Logger();
  final client = runWithOverrides(
    () => CodePushClient(
      httpClient: Auth().client,
      hostedUri: Uri.parse(shorebirdHostedURL),
    ),
  );

  /// Helper function to run a command in the shell, meant to be used in tests.
  ///
  /// It will take a command string, like `shorebird --version`, run it in the
  /// shell, and return the result.
  ///
  /// Output is printed as it arrives, so a command that hangs shows where.
  /// A command still running after [timeout] has its process tree, the
  /// thread stacks of every JVM (such as a Gradle daemon) and, on macOS, a
  /// sample of every Dart VM printed, is killed, and fails the test, rather
  /// than running into the job's timeout with nothing in the log.
  Future<ProcessResult> runCommand(
    String command, {
    required String workingDirectory,
    Duration timeout = const Duration(minutes: 8),
  }) async {
    final parts = command.split(' ');
    final executable = parts.first;
    final arguments = parts.skip(1).toList();
    logger.info('Running $command in $workingDirectory');
    final process = await Process.start(
      executable,
      arguments,
      runInShell: true,
      workingDirectory: workingDirectory,
    );
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          stdoutBuffer.writeln(line);
          logger.info(line);
        });
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          stderrBuffer.writeln(line);
          logger.info('stderr: $line');
        });
    int? exitedWith;
    unawaited(process.exitCode.then((code) => exitedWith = code));
    // The deadline covers the pipes too: a child that outlives the command
    // (such as a Gradle client) can hold them open after it exits.
    final exitCode =
        await Future.wait([
              process.exitCode,
              stdoutDone,
              stderrDone,
            ])
            .then<int?>((_) => exitedWith)
            .timeout(
              timeout,
              onTimeout: () async {
                logger.err(
                  exitedWith == null
                      ? '$command still running after $timeout.'
                      : '$command exited with $exitedWith, but a process it '
                            'started still held its output after $timeout.',
                );
                await _dumpAndKillProcessTree(process.pid, logger);
                return null;
              },
            );
    if (exitCode == null) {
      fail('$command timed out after $timeout');
    }
    logger.info('Exited with code: $exitCode');
    return ProcessResult(
      process.pid,
      exitCode,
      stdoutBuffer.toString(),
      stderrBuffer.toString(),
    );
  }

  test('--version', () async {
    final result = await runCommand(
      'shorebird --version',
      workingDirectory: '.',
    );
    expect(result.exitCode, equals(0));
    expect(result.stdout, stringContainsInOrder(['Engine', 'revision']));
  });

  // A launcher that drops the exit code turns every failure into a success,
  // which is what the Windows one did: each step below would then pass its
  // exit code check and fail later on a missing file.
  test('a failing command exits with its error code', () async {
    final result = await runCommand(
      'shorebird not-a-command',
      workingDirectory: '.',
    );
    expect(result.exitCode, equals(ExitCode.usage.code));
  });

  // Options after `--` go to Flutter, so shorebird must not parse them, and
  // the launcher must not drop the `--`.
  test('options after -- are not parsed as shorebird options', () async {
    final result = await runCommand(
      'shorebird --version -- --not-a-shorebird-option',
      workingDirectory: '.',
    );
    expect(result.exitCode, equals(ExitCode.success.code));
  });

  test(
    'create an app with a release and patch',
    () async {
      const releaseVersion = '1.0.0+1';
      const platform = 'android';
      const arch = 'aarch64';
      const channel = 'stable';

      final uuid = const Uuid().v4().replaceAll('-', '_');
      final testAppName = 'test_app_$uuid';
      final tempDir = Directory.systemTemp.createTempSync();
      final subDirWithSpace = Directory(
        p.join(tempDir.path, 'flutter directory'),
      )..createSync();
      var cwd = subDirWithSpace.path;

      // Create the default flutter counter app
      logger.info('running `shorebird create $testAppName` in $cwd');
      final createAppResult = await runCommand(
        'shorebird create $testAppName',
        workingDirectory: cwd,
      );
      expect(createAppResult.exitCode, equals(0));

      cwd = p.join(cwd, testAppName);

      final shorebirdYamlPath = p.join(cwd, 'shorebird.yaml');
      final shorebirdYamlText = File(shorebirdYamlPath).readAsStringSync();
      final shorebirdYaml = checkedYamlDecode(
        shorebirdYamlText,
        (m) => ShorebirdYaml.fromJson(m!),
      );

      // Delete the app however this test ends. Registering the cleanup here,
      // rather than only running it on the happy path at the bottom, is what
      // keeps a failing run from leaking an app: `getApps` returns the whole
      // account, so leaked test apps make that response slower for every
      // subsequent run until someone prunes them by hand.
      addTearDown(() async {
        try {
          await runWithOverrides(
            () => client.deleteApp(appId: shorebirdYaml.appId),
          );
        } on CodePushNotFoundException {
          // The happy path already deleted it.
        } on Exception catch (error) {
          logger.err('failed to delete ${shorebirdYaml.appId}: $error');
        }
      });

      // Verify that we have no releases for this app
      await expectLater(
        runWithOverrides(client.getApps),
        completion(
          contains(
            isA<AppMetadata>()
                .having((a) => a.appId, 'appId', shorebirdYaml.appId)
                .having(
                  (a) => a.latestReleaseVersion,
                  'latestReleaseVersion',
                  null,
                )
                .having((a) => a.latestPatchNumber, 'latestPatchNumber', null),
          ),
        ),
      );

      // Create an Android release.
      final shorebirdReleaseResult = await runCommand(
        'shorebird release android --verbose',
        workingDirectory: cwd,
      );
      expect(shorebirdReleaseResult.exitCode, equals(0));
      expect(
        shorebirdReleaseResult.stdout,
        contains('Published Release $releaseVersion!'),
      );

      // Verify that no patch is available.
      await expectLater(
        isPatchAvailable(
          appId: shorebirdYaml.appId,
          releaseVersion: releaseVersion,
          platform: platform,
          arch: arch,
          channel: channel,
        ),
        completion(isFalse),
      );

      // Verify that the release was created.
      await expectLater(
        runWithOverrides(client.getApps),
        completion(
          contains(
            isA<AppMetadata>()
                .having((a) => a.appId, 'appId', shorebirdYaml.appId)
                .having(
                  (a) => a.latestReleaseVersion,
                  'latestReleaseVersion',
                  releaseVersion,
                )
                .having((a) => a.latestPatchNumber, 'latestPatchNumber', null),
          ),
        ),
      );

      // Create an Android patch.
      final shorebirdPatchResult = await runCommand(
        'shorebird patch android --verbose',
        workingDirectory: cwd,
      );
      expect(shorebirdPatchResult.exitCode, equals(0));
      expect(shorebirdPatchResult.stdout, contains('Published Patch 1!'));

      // Verify that the patch is available.
      await expectLater(
        isPatchAvailable(
          appId: shorebirdYaml.appId,
          releaseVersion: releaseVersion,
          platform: platform,
          arch: arch,
          channel: channel,
        ),
        completion(isTrue),
      );

      // Verify that the patch was created.
      await expectLater(
        runWithOverrides(client.getApps),
        completion(
          contains(
            isA<AppMetadata>()
                .having((a) => a.appId, 'appId', shorebirdYaml.appId)
                .having(
                  (a) => a.latestReleaseVersion,
                  'latestReleaseVersion',
                  '1.0.0+1',
                )
                .having((a) => a.latestPatchNumber, 'latestPatchNumber', 1),
          ),
        ),
      );

      // Delete the app to clean up after ourselves. The tearDown registered
      // above is the safety net for a failing run; deleting here keeps the
      // assertion that the delete works.
      await expectLater(
        runWithOverrides(() => client.deleteApp(appId: shorebirdYaml.appId)),
        completes,
      );

      // Verify that the app was deleted.
      await expectLater(
        runWithOverrides(client.getApps),
        completion(
          isNot(
            contains(
              isA<AppMetadata>().having(
                (a) => a.appId,
                'appId',
                shorebirdYaml.appId,
              ),
            ),
          ),
        ),
      );

      // Verify that no patch is available.
      await expectLater(
        isPatchAvailable(
          appId: shorebirdYaml.appId,
          releaseVersion: releaseVersion,
          platform: platform,
          arch: arch,
          channel: channel,
        ),
        completion(isFalse),
      );
    },
    // Longer than runCommand's timeout, which says more than this one would,
    // plus the other commands' usual time. The job allows 30 minutes.
    timeout: const Timeout(Duration(minutes: 25)),
  );
}

Future<bool> isPatchAvailable({
  required String appId,
  required String releaseVersion,
  required String platform,
  required String arch,
  required String channel,
}) async {
  final response = await http.post(
    Uri.parse(
      Platform.environment['SHOREBIRD_HOSTED_URL']!,
    ).replace(path: '/api/v1/patches/check'),
    body: jsonEncode({
      'release_version': releaseVersion,
      'platform': platform,
      'arch': arch,
      'app_id': appId,
      'channel': channel,
    }),
  );
  if (response.statusCode != HttpStatus.ok) {
    throw Exception('Patch Check Failure: ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return json['patch_available'] as bool;
}

/// Prints the process tree under [root], every JVM's thread stacks and, on
/// macOS, every Dart VM's stacks, then kills the tree.
///
/// JVMs and Dart VMs are dumped whether or not they are in the tree: a Gradle
/// daemon is detached from the build that started it, and is where a hung
/// Android build usually waits, with `flutter assemble` running under it.
Future<void> _dumpAndKillProcessTree(int root, Logger logger) async {
  const dumpTimeout = Duration(seconds: 30);
  if (Platform.isWindows) {
    try {
      final tasks = await Process.run('tasklist', ['/v']).timeout(dumpTimeout);
      logger.info('Processes:\n${tasks.stdout}');
    } finally {
      await Process.run('taskkill', ['/T', '/F', '/PID', '$root']);
    }
    return;
  }

  final tree = {root};
  try {
    final ps = await Process.run('ps', [
      '-A',
      '-o',
      'pid=,ppid=,etime=,command=',
    ]).timeout(dumpTimeout);
    final rows = [
      for (final line in LineSplitter.split(ps.stdout as String))
        line.trim().split(RegExp(r'\s+')),
    ].where((row) => row.length >= 4 && int.tryParse(row[0]) != null).toList();
    var grew = true;
    while (grew) {
      grew = false;
      for (final row in rows) {
        if (tree.contains(int.tryParse(row[1])) &&
            tree.add(int.parse(row[0]))) {
          grew = true;
        }
      }
    }
    logger.info('Process tree:');
    for (final row in rows) {
      if (tree.contains(int.parse(row[0]))) logger.info(row.join(' '));
    }

    final javaHome = Platform.environment['JAVA_HOME'];
    final jcmd = javaHome == null ? 'jcmd' : p.join(javaHome, 'bin', 'jcmd');
    for (final row in rows) {
      final commandLine = row.sublist(3).join(' ');
      if (p.basename(row[3]) != 'java') continue;
      logger.info('Threads of JVM ${row[0]} ($commandLine):');
      try {
        final dump = await Process.run(jcmd, [
          row[0],
          'Thread.print',
        ]).timeout(dumpTimeout);
        logger.info('${dump.stdout}${dump.stderr}');
      } on Exception catch (error) {
        logger.info('could not dump: $error');
      }
    }

    // On macOS arm64 the host Dart VM can deadlock at a safepoint, so sample
    // the stacks of every Dart VM but this test's own.
    if (Platform.isMacOS) {
      for (final row in rows) {
        // dart:io's pid: skip this test's own VM.
        if (int.parse(row[0]) == pid) continue;
        if (!const {
          'dart',
          'dartvm',
          'dartaotruntime',
        }.contains(p.basename(row[3]))) {
          continue;
        }
        logger.info(
          'Stacks of Dart VM ${row[0]} (${row.sublist(3).join(' ')}):',
        );
        try {
          final sample = await Process.run('sample', [
            row[0],
            '3',
          ]).timeout(dumpTimeout);
          logger.info('${sample.stdout}${sample.stderr}');
        } on Exception catch (error) {
          logger.info('could not sample: $error');
        }
      }
    }
  } finally {
    for (final id in tree) {
      Process.killPid(id, ProcessSignal.sigkill);
    }
  }
}
