// This script tests that a patch can be successfully created.
// It creates a new empty, flutter project, initializes Shorebird,
// creates a new release, patches the release
//
// It is a simpler version of the "patch_e2e.sh`, which in addition
// to creating a patch, it ensures that the patch is applied correctly.
//
// This script is intended to be run in all platforms (Linux, MacOS, Windows),
// and for that reason it is written in dart.
//
// Pre-requisites:
// - Flutter must be installed.
// - Android SDK must be installed.
// - Shorebird must be installed.
//
// Usage: dart create_patch_e2e.dart
import 'dart:io';

void main() {
  // Intentionally including a space and a non ascii char in the path.
  final dir = Directory(
    joinPath([Directory.systemTemp.path, 'shorebird workspace-XXXXX 木']),
  )..createSync();

  stdout.writeln('Directory created: ${dir.path}');

  const projectName = 'e2e_test';
  final projectCreationResult = Process.runSync(
    'flutter',
    ['create', projectName, '--empty', '--platforms', 'android'],
    workingDirectory: dir.path,
  );

  final projectDir = joinPath([dir.path, projectName]);

  _checkResult(projectCreationResult);
  stdout.writeln('Project created successfully');

  final shorebirdInitResult = Process.runSync(
    'shorebird',
    [
      'init',
      '-f',
      '-v',
    ],
    workingDirectory: projectDir,
  );

  _checkResult(shorebirdInitResult);
  stdout.writeln('Shorebird initialized successfully');

  final releaseResult = Process.runSync(
    'shorebird',
    [
      'release',
      'android',
      '-v',
    ],
    workingDirectory: projectDir,
  );

  _checkResult(releaseResult);
  stdout.writeln('Release created successfully');

  final patchResult = Process.runSync(
    'shorebird',
    [
      'patch',
      'android',
      '-v',
      '--release-version',
      '0.1.0+1',
    ],
    workingDirectory: projectDir,
  );

  _checkResult(patchResult);

  stdout.write('Patch created successfully.\n');
  exit(0);
}

// So we don't use package just for this.
String joinPath(List<String> parts) {
  return parts.join(Platform.pathSeparator);
}

void _checkResult(ProcessResult result) {
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) {
    exit(result.exitCode);
  }
}
