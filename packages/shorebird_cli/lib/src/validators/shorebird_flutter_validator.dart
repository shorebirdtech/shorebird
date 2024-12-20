import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// An exception thrown when a validation issue is found.
class FlutterValidationException implements Exception {
  /// Creates a new [FlutterValidationException] with the provided [message].
  const FlutterValidationException(this.message);

  /// The message associated with the exception.
  final String message;

  @override
  String toString() => 'FlutterValidationException: $message';
}

/// An exception thrown when a command is not found.
class CommandNotFoundException implements Exception {}

/// {@template shorebird_flutter_validator}
/// Compares the version of Flutter that Shorebird includes with the version
/// of Flutter on the user's path. Will error if no system Flutter is found, and
/// will warn if major or minor versions differ.
/// {@endtemplate}
class ShorebirdFlutterValidator extends Validator {
  /// {@macro shorebird_flutter_validator}
  ShorebirdFlutterValidator();

  @override
  String get description => 'Flutter install is correct';

  @override
  Future<List<ValidationIssue>> validate() async {
    final issues = <ValidationIssue>[];

    if (!shorebirdEnv.flutterDirectory.existsSync()) {
      final message =
          'No Flutter directory found at ${shorebirdEnv.flutterDirectory}';
      issues.add(ValidationIssue.error(message: message));
    }

    if (!await shorebirdFlutter.isUnmodified()) {
      issues.add(
        ValidationIssue.warning(
          message: '${shorebirdEnv.flutterDirectory} has local modifications',
        ),
      );
    }

    String? shorebirdFlutterVersionString;
    try {
      shorebirdFlutterVersionString = await _getFlutterVersion();
    } on Exception catch (error) {
      issues.add(
        ValidationIssue.error(
          message: 'Failed to determine Shorebird Flutter version. $error',
        ),
      );
    }

    String? pathFlutterVersionString;
    try {
      pathFlutterVersionString = await _getFlutterVersion(
        useVendedFlutter: false,
      );
    } on CommandNotFoundException catch (_) {
      // If there is no system Flutter, we don't throw a validation exception.
    } on Exception catch (error) {
      issues.add(
        ValidationIssue.error(
          message: 'Failed to determine path Flutter version. $error',
        ),
      );
    }

    if (shorebirdFlutterVersionString != null &&
        pathFlutterVersionString != null) {
      final shorebirdFlutterVersion =
          Version.parse(shorebirdFlutterVersionString);
      final pathFlutterVersion = Version.parse(pathFlutterVersionString);
      if (shorebirdFlutterVersion.major != pathFlutterVersion.major ||
          shorebirdFlutterVersion.minor != pathFlutterVersion.minor) {
        final message = '''
The version of Flutter that Shorebird includes and the Flutter on your path are different.
\tShorebird Flutter: $shorebirdFlutterVersionString
\tSystem Flutter:    $pathFlutterVersionString
This can cause unexpected behavior if you are switching between the tools and the version gap is wide. If you have any trouble, please let us know on Shorebird discord.''';

        issues.add(ValidationIssue.warning(message: message));
      }
    }

    final flutterStorageEnvironmentValue =
        platform.environment['FLUTTER_STORAGE_BASE_URL'];
    if (flutterStorageEnvironmentValue != null &&
        flutterStorageEnvironmentValue.isNotEmpty) {
      issues.add(
        ValidationIssue.warning(
          message: 'Shorebird does not respect the FLUTTER_STORAGE_BASE_URL '
              'environment variable at this time',
        ),
      );
    }

    return issues;
  }

  Future<String> _getFlutterVersion({bool useVendedFlutter = true}) async {
    final String? version;
    try {
      version = useVendedFlutter
          ? await shorebirdFlutter.getVersionString()
          : await shorebirdFlutter.getSystemVersion();
    } on ProcessException catch (error) {
      if (error.errorCode == 127) throw CommandNotFoundException();

      throw FlutterValidationException(
        'Flutter version check did not complete successfully. ${error.message}',
      );
    }

    if (version == null) {
      throw const FlutterValidationException(
        'Could not detect version number in output',
      );
    }

    return version;
  }
}
