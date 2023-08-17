import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  final logger = Logger();
  final client = runScoped(
    () => CodePushClient(
      httpClient: Auth().client,
      hostedUri: Uri.parse(Platform.environment['SHOREBIRD_HOSTED_URL']!),
    ),
    values: {platformRef},
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

  test('create an app with a release and patch', () async {
    final authToken = Platform.environment['SHOREBIRD_TOKEN'];
    if (authToken == null || authToken.isEmpty) {
      throw Exception('SHOREBIRD_TOKEN environment variable is not set.');
    }

    final uuid = const Uuid().v4().replaceAll('-', '_');
    final testAppName = 'test_app_$uuid';
    final tempDir = Directory.systemTemp.createTempSync();
    final subDirWithSpace = Directory(p.join(tempDir.path, 'flutter directory'))
      ..createSync();
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
      'shorebird init',
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
      client.getApps(),
      completion(
        equals([
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
        ]),
      ),
    );

    // Create an Android release.
    final shorebirdReleaseResult = runCommand(
      'shorebird release android --force',
      workingDirectory: cwd,
    );
    expect(shorebirdReleaseResult.stderr, isEmpty);
    expect(shorebirdReleaseResult.stdout, contains('Published Release!'));
    expect(shorebirdReleaseResult.exitCode, equals(0));

    // Verify that the release was created.
    await expectLater(
      client.getApps(),
      completion(
        equals([
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
                null,
              ),
        ]),
      ),
    );

    // Create an Android patch.
    final shorebirdPatchResult = runCommand(
      'shorebird patch android --force',
      workingDirectory: cwd,
    );
    expect(shorebirdPatchResult.stderr, isEmpty);
    expect(shorebirdPatchResult.stdout, contains('Published Patch!'));
    expect(shorebirdPatchResult.exitCode, equals(0));

    // Verify that the patch was created.
    await expectLater(
      client.getApps(),
      completion(
        equals([
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
        ]),
      ),
    );

    // Delete the app to clean up after ourselves.
    await expectLater(client.deleteApp(appId: shorebirdYaml.appId), completes);

    // Verify that the app was deleted.
    await expectLater(client.getApps(), completion(isEmpty));
  });
}
