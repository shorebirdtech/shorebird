import 'package:shorebird_cli/src/platform/apple/apple_platform.dart';

/// {@template missing_xcode_project_exception}
/// Thrown when the Flutter project has an ios or macos folder that is missing
/// an Xcode project.
/// {@endtemplate}
class MissingXcodeProjectException implements Exception {
  /// {@macro missing_xcode_project_exception}
  const MissingXcodeProjectException({
    required this.platformFolderPath,
    required this.platform,
  });

  /// Expected path of the Xcode project.
  final String platformFolderPath;

  /// The platform that is missing an Xcode project.
  final ApplePlatform platform;

  @override
  String toString() {
    return '''
Could not find an Xcode project in $platformFolderPath.
If your project does not support ${platform.name}, you can safely remove $platformFolderPath.
Otherwise, to repair ${platform.name}, run "flutter create . --platforms ${platform.name}"''';
  }
}
