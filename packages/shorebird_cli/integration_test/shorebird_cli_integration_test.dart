import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/config/config.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  final logger = Logger();

  ProcessResult runShorebirdCommand(
    String command, {
    required String workingDirectory,
  }) {
    logger.info('running shorebird $command in $workingDirectory');
    return Process.runSync(
      'shorebird',
      command.split(' '),
      runInShell: true,
      workingDirectory: workingDirectory,
    );
  }

  test('--version', () {
    final result = runShorebirdCommand('--version', workingDirectory: '.');
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
    final createAppResult = Process.runSync(
      'flutter',
      ['create', testAppName],
      runInShell: true,
      workingDirectory: cwd,
    );
    expect(createAppResult.stderr, isEmpty);
    expect(createAppResult.exitCode, equals(0));

    cwd = p.join(cwd, testAppName);

    // Initialize Shorebird
    final initShorebirdResult = runShorebirdCommand(
      'init',
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

    // Run the doctor command. This should yield a warning about the
    // AndroidManifest.xml not containing the internet permission and suggest
    // that the user run `shorebird doctor --fix`.
    final shorebirdDoctorResult = runShorebirdCommand(
      'doctor',
      workingDirectory: cwd,
    );
    expect(shorebirdDoctorResult.stderr, isEmpty);
    expect(shorebirdDoctorResult.stdout, contains('shorebird doctor --fix'));
    expect(shorebirdDoctorResult.exitCode, equals(0));

    // Run the suggested `doctor --fix` command.
    final shorebirdDoctorFixResult = runShorebirdCommand(
      'doctor --fix',
      workingDirectory: cwd,
    );
    expect(shorebirdDoctorFixResult.stderr, isEmpty);
    expect(shorebirdDoctorFixResult.exitCode, equals(0));

    // Verify that we have no releases for this app
    final preReleaseAppsListResult = runShorebirdCommand(
      'apps list',
      workingDirectory: cwd,
    );
    expect(preReleaseAppsListResult.stderr, isEmpty);
    expect(preReleaseAppsListResult.exitCode, equals(0));
    expect(
      (preReleaseAppsListResult.stdout as String).split('\n'),
      anyElement(
        matches('^.+$testAppName.+${shorebirdYaml.appId}.+--.+--.+\$'),
      ),
    );

    // Create an Android release.
    final shorebirdReleaseResult = runShorebirdCommand(
      'release android --force',
      workingDirectory: cwd,
    );
    expect(shorebirdReleaseResult.stderr, isEmpty);
    expect(shorebirdReleaseResult.stdout, contains('Published Release!'));
    expect(shorebirdReleaseResult.exitCode, equals(0));

    // Verify that the release was created.
    final postReleaseAppsListResult = runShorebirdCommand(
      'apps list',
      workingDirectory: cwd,
    );
    expect(postReleaseAppsListResult.stderr, isEmpty);
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
    final shorebirdPatchResult = runShorebirdCommand(
      'patch android --force',
      workingDirectory: cwd,
    );
    expect(shorebirdPatchResult.stderr, isEmpty);
    expect(shorebirdPatchResult.stdout, contains('Published Patch!'));
    expect(shorebirdPatchResult.exitCode, equals(0));

    // Verify that the release was created.
    final postPatchAppsListResult = runShorebirdCommand(
      'apps list',
      workingDirectory: cwd,
    );
    expect(postPatchAppsListResult.stderr, isEmpty);
    expect(postPatchAppsListResult.exitCode, equals(0));
    expect(
      (postPatchAppsListResult.stdout as String).split('\n'),
      anyElement(
        matches(
          '^.+$testAppName.+${shorebirdYaml.appId}.+1\\.0\\.0\\+1.+1.+\$',
        ),
      ),
    );
  });
}
