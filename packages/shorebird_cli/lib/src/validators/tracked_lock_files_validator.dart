import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/executables/git.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Checks that .lock files (pubspec.lock, Podfile.lock) are tracked in source
/// control if they exist and if the project is part of a git repository.
class TrackedLockFilesValidator extends Validator {
  @override
  String get description => 'Lock files are tracked in source control';

  @override
  bool canRunInCurrentContext() => shorebirdEnv.hasPubspecYaml;

  @override
  Future<List<ValidationIssue>> validate() async {
    final projectRoot = shorebirdEnv.getFlutterProjectRoot();
    if (projectRoot == null) {
      return [];
    }

    final isGitRepo = await git.isGitRepo(directory: projectRoot);
    if (!isGitRepo) {
      return [
        ValidationIssue.warning(
          message:
              '''This project is not tracked in git. We recommend using source control.''',
        ),
      ];
    }

    final lockFilePaths = [
      'pubspec.lock',
      p.join('ios', 'Podfile.lock'),
      p.join('macos', 'Podfile.lock'),
    ];

    final warnings = <ValidationIssue>[];
    for (final path in lockFilePaths) {
      final file = File(p.join(projectRoot.path, path));
      if (await _fileExistsAndIsNotTracked(file)) {
        warnings.add(
          ValidationIssue.warning(
            message:
                '''$path is not tracked in source control. We recommend tracking lock files in source control to avoid unexpected dependency version changes.''',
          ),
        );
      }
    }

    return warnings;
  }

  /// Returns true if [file] exists but is not tracked in git.
  Future<bool> _fileExistsAndIsNotTracked(File file) async {
    return file.existsSync() && !(await git.isFileTracked(file: file));
  }
}
