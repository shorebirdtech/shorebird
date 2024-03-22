import 'dart:convert';
import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/http_client/http_client.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

R runWithOverrides<R>(R Function() body) {
  return runScoped(
    body,
    values: {authRef, httpClientRef, loggerRef, platformRef},
  );
}

void main() {
  final logger = Logger();
  final client = runWithOverrides(
    () => CodePushClient(
      httpClient: Auth().client,
      hostedUri: Uri.parse(Platform.environment['SHOREBIRD_HOSTED_URL']!),
    ),
  );

  ProcessResult runCommand(
    String command, {
    required String workingDirectory,
  }) {
    final parts = command.split(' ');
    final executable = parts.first;
    final arguments = parts.skip(1).toList();
    logger.info('running $command in $workingDirectory');
    return Process.runSync(
      executable,
      arguments,
      runInShell: true,
      workingDirectory: workingDirectory,
    );
  }

  test('--version', () {
    final result = runCommand('shorebird --version', workingDirectory: '.');
    expect(result.stderr, isEmpty);
    expect(
      result.stdout,
      stringContainsInOrder(['Engine', 'revision']),
    );
    expect(result.exitCode, equals(0));
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
      final subDirWithSpace =
          Directory(p.join(tempDir.path, 'flutter directory'))..createSync();
      var cwd = subDirWithSpace.path;

      // Create the default flutter counter app
      logger.info('running `flutter create $testAppName` in $cwd');
      final createAppResult = runCommand(
        'flutter create $testAppName',
        workingDirectory: cwd,
      );
      expect(createAppResult.stderr, isEmpty);
      expect(createAppResult.exitCode, equals(0));

      cwd = p.join(cwd, testAppName);

      // Initialize Shorebird
      final initShorebirdResult = runCommand(
        'shorebird init --verbose',
        workingDirectory: cwd,
      );
      expect(initShorebirdResult.stderr, isEmpty);
      expect(initShorebirdResult.exitCode, equals(0));

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
                .having(
                  (a) => a.appId,
                  'appId',
                  shorebirdYaml.appId,
                )
                .having(
                  (a) => a.latestReleaseVersion,
                  'latestReleaseVersion',
                  null,
                )
                .having(
                  (a) => a.latestPatchNumber,
                  'latestPatchNumber',
                  null,
                ),
          ),
        ),
      );

      // Create an Android release.
      final shorebirdReleaseResult = runCommand(
        'shorebird release android --verbose',
        workingDirectory: cwd,
      );
      expect(shorebirdReleaseResult.stderr, isEmpty);
      expect(
        shorebirdReleaseResult.stdout,
        contains('Published Release $releaseVersion!'),
      );
      expect(shorebirdReleaseResult.exitCode, equals(0));

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
                .having(
                  (a) => a.appId,
                  'appId',
                  shorebirdYaml.appId,
                )
                .having(
                  (a) => a.latestReleaseVersion,
                  'latestReleaseVersion',
                  releaseVersion,
                )
                .having(
                  (a) => a.latestPatchNumber,
                  'latestPatchNumber',
                  null,
                ),
          ),
        ),
      );

      // Create an Android patch.
      final shorebirdPatchResult = runCommand(
        'shorebird patch android --verbose',
        workingDirectory: cwd,
      );
      expect(shorebirdPatchResult.stderr, isEmpty);
      expect(shorebirdPatchResult.stdout, contains('Published Patch 1!'));
      expect(shorebirdPatchResult.exitCode, equals(0));

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
                .having(
                  (a) => a.appId,
                  'appId',
                  shorebirdYaml.appId,
                )
                .having(
                  (a) => a.latestReleaseVersion,
                  'latestReleaseVersion',
                  '1.0.0+1',
                )
                .having(
                  (a) => a.latestPatchNumber,
                  'latestPatchNumber',
                  1,
                ),
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
    timeout: const Timeout(Duration(minutes: 5)),
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
    Uri.parse(Platform.environment['SHOREBIRD_HOSTED_URL']!).replace(
      path: '/api/v1/patches/check',
    ),
    body: jsonEncode(
      {
        'release_version': releaseVersion,
        'platform': platform,
        'arch': arch,
        'app_id': appId,
        'channel': channel,
      },
    ),
  );
  if (response.statusCode != HttpStatus.ok) {
    throw Exception('Patch Check Failure: ${response.statusCode}');
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  return json['patch_available'] as bool;
}
