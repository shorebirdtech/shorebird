import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Checks that ios/Runner.xcodeproj/project.pbxproj does *not* assign any
/// `FLUTTER_`-prefixed build setting. Flutter itself populates these at
/// runtime or via the generated `ios/Flutter/Generated.xcconfig` (which we
/// do not scan), so a hard-coded assignment in `project.pbxproj` can cause
/// different versions of Flutter to be used during different parts of the
/// build, potentially causing build failures.
class XcodeprojFlutterOverrideValidator extends Validator {
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
      'Xcode project does not override FLUTTER_ build settings';

  @override
  Future<List<ValidationIssue>> validate() async {
    final root = shorebirdEnv.getFlutterProjectRoot();
    if (root == null) {
      return [];
    }

    final pbxProjFile = File(p.join(root.path, _projectPbxprojPath));
    if (!pbxProjFile.existsSync()) {
      // No iOS Xcode project to scan (e.g. Flutter module used for add-to-app,
      // or a project with no iOS platform). Nothing to validate.
      return [];
    }

    final overrides = _flutterOverridesIn(pbxProjFile);
    if (overrides.isEmpty) {
      return [];
    }

    final names = overrides.join(', ');
    return [
      ValidationIssue(
        severity: ValidationIssueSeverity.error,
        message:
            '$_projectPbxprojPath overrides FLUTTER_ build setting(s): $names. '
            'FLUTTER_* variables are set by Flutter (at runtime or via '
            'ios/Flutter/Generated.xcconfig) and should not be hard-coded '
            'in the Xcode project.',
      ),
    ];
  }

  /// Returns the distinct set of `FLUTTER_*` names that are *assigned* in the
  /// given pbxproj contents (not merely referenced via `$(NAME)` or `$NAME`).
  Set<String> _flutterOverridesIn(File pbxProjFile) {
    // We could consider using package:xcode_parser, but for now this should
    // be sufficient.
    final contents = pbxProjFile.readAsStringSync();
    // Match FLUTTER_<NAME> assignments in various formats:
    // - FLUTTER_FOO = value;
    // - FLUTTER_FOO = "value";
    // - FLUTTER_FOO = $(FLUTTER_FOO);
    // Allow flexible spacing around the equals sign.
    // Use a negative lookahead on `//` to avoid line comments, and require
    // the assignment to terminate with `;` on the same line. Note: this does
    // not strip pbxproj `/* ... */` block comments, so a commented-out
    // assignment inside one would still be flagged. That's acceptable since
    // it still represents an intent to set FLUTTER_*.
    final matcher = RegExp(
      r'^(?!\s*//).*?(FLUTTER_\w+)\s*=\s*[^;\n]+;',
      multiLine: true,
    );
    return {
      for (final match in matcher.allMatches(contents)) match.group(1)!,
    };
  }
}
