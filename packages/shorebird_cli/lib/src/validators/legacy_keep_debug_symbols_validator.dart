import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/flutter_version_constraints.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Warns when `android/app/build.gradle.kts` (or its Groovy sibling) contains
/// a legacy `packaging.jniLibs.keepDebugSymbols.add("**/libapp.so")` line on
/// projects that target Flutter 3.44 or newer.
///
/// Background:
///
/// Upstream Flutter PR https://github.com/flutter/flutter/pull/181275 (merged
/// 2026-01-26, first shipped in 3.44) inverted the responsibility for
/// stripping `libapp.so`. Before 3.44 Flutter stripped the AOT shared library
/// itself, so users (and the e2e test fixture) added the AGP-level
/// `keepDebugSymbols` exclusion to keep `libapp.so` byte-stable for Shorebird
/// patch diffing. From 3.44 onward, Flutter expects the Android Gradle Plugin
/// (AGP) to strip the library and produce the matching `libapp.so.sym`
/// companion in the AAB's BUNDLE-METADATA, and flutter_tools adds a
/// post-build verification that fatal-errors when that companion is missing.
///
/// The legacy line tells AGP to skip stripping `libapp.so`, which prevents
/// the `.sym` from being produced and causes the new verification to fail.
/// On 3.44+ the line is unnecessary as well as actively harmful, so we surface
/// a warning that points the user at the exact file and substring to remove.
///
/// On older Flutter versions the line is still appropriate and this validator
/// is a no-op.
class LegacyKeepDebugSymbolsValidator extends Validator {
  /// The substring we treat as a match. Catches `add(...)` and `+=` forms,
  /// single-quoted and double-quoted, with arbitrary whitespace around the
  /// `(` or `+=`, since users may have hand-edited the line.
  static final _legacyKeepDebugSymbolsPattern = RegExp(
    r'''keepDebugSymbols\s*(?:\.add\s*\(|\+=)\s*['"][^'"]*\*\*/libapp\.so['"]''',
  );

  @override
  String get description =>
      'android/app/build.gradle(.kts) does not contain a legacy '
      'keepDebugSymbols line for libapp.so';

  @override
  bool canRunInCurrentContext() {
    if (_androidAppDirectory == null) return false;
    return _gradleFiles.any((f) => f.existsSync());
  }

  // coverage:ignore-start
  @override
  String? get incorrectContextMessage =>
      'No android/app directory was found, so this validator does not apply.';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    final flutterRevision = shorebirdEnv.flutterRevision;
    final flutterVersion = await shorebirdFlutter.resolveFlutterVersion(
      flutterRevision,
    );
    final agpStripsLibapp = libappStrippedByAgpConstraint.isSatisfiedBy(
      // Treat unknown versions as satisfying the constraint so users who
      // are pinned to a development revision (where resolveFlutterVersion
      // returns null) still get the migration nudge. False positives on
      // unrelated dev branches are preferable to silently missing a real
      // breakage on the upgrade path.
      version: flutterVersion ?? libappStrippedByAgpConstraint.minVersion,
      revision: flutterRevision,
    );
    if (!agpStripsLibapp) return [];

    final issues = <ValidationIssue>[];
    for (final gradleFile in _gradleFiles) {
      if (!gradleFile.existsSync()) continue;
      final contents = gradleFile.readAsStringSync();
      if (!_legacyKeepDebugSymbolsPattern.hasMatch(contents)) continue;
      final relativePath = p.relative(
        gradleFile.path,
        from: shorebirdEnv.getFlutterProjectRoot()!.path,
      );
      issues.add(
        ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message:
              '$relativePath contains a legacy '
              '`packaging.jniLibs.keepDebugSymbols.add("**/libapp.so")` '
              'line. Flutter 3.44 (PR flutter/flutter#181275) requires '
              'AGP to strip libapp.so and emit a `libapp.so.sym` '
              'companion. The legacy line blocks AGP from stripping, '
              'which causes builds to fail or skips Play Console crash '
              'symbols for Dart code. Remove the line.',
        ),
      );
    }
    return issues;
  }

  Directory? get _androidAppDirectory {
    final root = shorebirdEnv.getFlutterProjectRoot();
    if (root == null) return null;
    return Directory(p.join(root.path, 'android', 'app'));
  }

  List<File> get _gradleFiles {
    final appDir = _androidAppDirectory;
    if (appDir == null) return const [];
    return [
      File(p.join(appDir.path, 'build.gradle.kts')),
      File(p.join(appDir.path, 'build.gradle')),
    ];
  }
}
