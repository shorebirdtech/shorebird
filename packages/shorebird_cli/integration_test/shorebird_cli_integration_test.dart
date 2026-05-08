import 'dart:convert';
import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
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
    values: {authRef, httpClientRef, loggerRef, platformRef, shorebirdEnvRef},
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
  ProcessResult runCommand(
    String command, {
    required String workingDirectory,
    Logger? logger,
  }) {
    logger ??= Logger();
    final parts = command.split(' ');
    final executable = parts.first;
    final arguments = parts.skip(1).toList();
    logger.info('Running $command in $workingDirectory');
    final result = Process.runSync(
      executable,
      arguments,
      runInShell: true,
      workingDirectory: workingDirectory,
    );
    logger
      ..info('Exited with code: ${result.exitCode}')
      ..info(result.stdout.toString());
    if (result.exitCode != ExitCode.success.code) {
      logger.err(result.stderr.toString());
    }
    return result;
  }

  test('--version', () {
    final result = runCommand('shorebird --version', workingDirectory: '.');
    expect(result.exitCode, equals(0));
    expect(result.stdout, stringContainsInOrder(['Engine', 'revision']));
  });

  test(
    'create an app with a release and patch',
    () async {
      final authToken = Platform.environment[shorebirdTokenEnvVar];
      if (authToken == null || authToken.isEmpty) {
        throw Exception(
          '$shorebirdTokenEnvVar environment variable is not set.',
        );
      }
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
      final createAppResult = runCommand(
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
      final shorebirdReleaseResult = runCommand(
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
      final shorebirdPatchResult = runCommand(
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

      // Delete the app to clean up after ourselves.
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
    timeout: const Timeout(Duration(minutes: 15)),
  );

  group('fallback API endpoint', () {
    // RFC 2606 reserves `.invalid` for testing; resolvers return NXDOMAIN
    // immediately, producing a fast transport-level failure.
    final unreachable = Uri.parse('https://api.fallback-test.invalid');
    final reachable = Uri.parse(shorebirdHostedURL);

    /// Exercises one read against the API. A successful return or a
    /// [CodePushException] both prove the connection layer succeeded
    /// (the latter is just a 4xx HTTP response). A [SocketException]
    /// proves it did not.
    Future<void> hitApi(CodePushClient client) async {
      try {
        await client.getCurrentUser();
      } on CodePushException {
        // HTTP-level error means the request reached an origin. Acceptable
        // for these tests which only verify connection-layer routing.
      }
    }

    test('uses primary when reachable, never contacts fallback', () async {
      final client = runWithOverrides(
        () => CodePushClient(
          httpClient: Auth().client,
          hostedUri: reachable,
          fallbackHostedUri: unreachable,
        ),
      );
      // If the primary fails for any reason, the fallback is unreachable
      // and the call would surface a SocketException. No exception means
      // the primary succeeded.
      await hitApi(client);
    });

    test('falls over to fallback when primary is unreachable', () async {
      final client = runWithOverrides(
        () => CodePushClient(
          httpClient: Auth().client,
          hostedUri: unreachable,
          fallbackHostedUri: reachable,
        ),
      );
      // Primary will fail with a SocketException at DNS resolution.
      // Fallback should succeed.
      await hitApi(client);
    });

    test('surfaces transport error when both endpoints are unreachable', () {
      final client = runWithOverrides(
        () => CodePushClient(
          httpClient: Auth().client,
          hostedUri: Uri.parse('https://primary.fallback-test.invalid'),
          fallbackHostedUri: Uri.parse(
            'https://fallback.fallback-test.invalid',
          ),
        ),
      );
      expect(
        client.getCurrentUser(),
        throwsA(isA<SocketException>()),
      );
    });
  });
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
