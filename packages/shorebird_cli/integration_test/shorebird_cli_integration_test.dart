import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/config/config.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  final logger = Logger();

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
      stringContainsInOrder(['Shorebird Engine', 'revision']),
    );
    expect(result.exitCode, equals(0));
  });

  test('create an app with a release and patch', () {
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
    final preReleaseAppsListResult = runCommand(
      'shorebird apps list',
      workingDirectory: cwd,
    );
    expect(preReleaseAppsListResult.exitCode, equals(0));
    expect(
      (preReleaseAppsListResult.stdout as String).split('\n'),
      anyElement(
        matches('^.+$testAppName.+${shorebirdYaml.appId}.+--.+--.+\$'),
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
    final postReleaseAppsListResult = runCommand(
      'shorebird apps list',
      workingDirectory: cwd,
    );
    expect(postReleaseAppsListResult.exitCode, equals(0));
    expect(
      (postReleaseAppsListResult.stdout as String).split('\n'),
      anyElement(
        matches(
          '^.+$testAppName.+${shorebirdYaml.appId}.+1\\.0\\.0\\+1.+--.+\$',
        ),
      ),
    );

    // Create an Android patch.
    final shorebirdPatchResult = runCommand(
      'shorebird patch android --release-version 1.0.0+1 --force',
      workingDirectory: cwd,
    );
    expect(shorebirdPatchResult.stderr, isEmpty);
    expect(shorebirdPatchResult.stdout, contains('Published Patch!'));
    expect(shorebirdPatchResult.exitCode, equals(0));

    // Verify that the patch was created.
    final postPatchAppsListResult = runCommand(
      'shorebird apps list',
      workingDirectory: cwd,
    );
    expect(postPatchAppsListResult.exitCode, equals(0));
    expect(
      (postPatchAppsListResult.stdout as String).split('\n'),
      anyElement(
        matches(
          '^.+$testAppName.+${shorebirdYaml.appId}.+1\\.0\\.0\\+1.+1.+\$',
        ),
      ),
    );

    // Delete the app to clean up after ourselves.
    final deleteAppResult = runCommand(
      'shorebird apps delete --app-id=${shorebirdYaml.appId} --force',
      workingDirectory: cwd,
    );
    expect(deleteAppResult.exitCode, equals(0));
    expect(
      deleteAppResult.stdout,
      contains('Deleted app: ${shorebirdYaml.appId}'),
    );

    // Verify that the app was deleted.
    final deleteAppAppsListResult = runCommand(
      'shorebird apps list',
      workingDirectory: cwd,
    );
    expect(deleteAppAppsListResult.exitCode, equals(0));
    expect(
      (deleteAppAppsListResult.stdout as String).split('\n'),
      isNot(
        anyElement(
          matches(
            '^.+$testAppName.+${shorebirdYaml.appId}.+\$',
          ),
        ),
      ),
    );
  });
}
