import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Checks that ios/Runner.xcodeproj/project.pbxproj does *not* contain
/// FLUTTER_ROOT environment overrides.  Doing so could cause different
/// versions of Flutter to be used during different parts of the build process
/// potentially causing build failures.
class XcodeprojFlutterRootValidator extends Validator {
  static final String _iosRunnerXCodeProjPath = p.join(
    'ios',
    'Runner.xcodeproj',
  );

  /// Path to the project.pbxproj file.
  static final String _projectPbxprojPath = p.join(
    _iosRunnerXCodeProjPath,
    'project.pbxproj',
  );

  @override
  String get description =>
      'Xcode project does not override FLUTTER_ROOT environment variable';

  @override
  bool canRunInCurrentContext() =>
      _iosRunnerXcodeprojDirectory?.existsSync() ?? false;

  // coverage:ignore-start
  @override
  String get incorrectContextMessage =>
      '''
The ${_iosRunnerXcodeprojDirectory?.path ?? _iosRunnerXCodeProjPath} directory does not exist.

The command you are running must be run within a Flutter app project that supports the iOS platform.''';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    final pbxProjFile = File(_projectPbxprojPath);
    if (!pbxProjFile.existsSync()) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: '''No project.pbxproj file found at $_projectPbxprojPath''',
        ),
      ];
    }

    if (_projectPbxprojHasFlutterRootOverride(pbxProjFile)) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: '$_projectPbxprojPath contains a FLUTTER_ROOT override.',
        ),
      ];
    }

    return [];
  }

  Directory? get _iosRunnerXcodeprojDirectory {
    final root = shorebirdEnv.getFlutterProjectRoot();
    if (root == null) return null;
    return Directory(p.join(root.path, 'ios', 'Runner.xcodeproj'));
  }

  bool _projectPbxprojHasFlutterRootOverride(File pbxProjFile) {
    // We could consider using package:xcode_parser, but for now this should
    // be sufficient.
    final contents = pbxProjFile.readAsStringSync();
    // Match FLUTTER_ROOT assignments in various formats:
    // - FLUTTER_ROOT = value;
    // - FLUTTER_ROOT = "value";
    // - FLUTTER_ROOT = $(FLUTTER_ROOT);
    // Allow for flexible spacing around the equals sign
    final matcher = RegExp(r'FLUTTER_ROOT\s*=\s*[^;]+;', multiLine: true);
    return matcher.hasMatch(contents);
  }
}
