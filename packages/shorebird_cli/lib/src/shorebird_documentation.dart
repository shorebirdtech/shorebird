import 'package:mason_logger/mason_logger.dart';

/// Link to the Shorebird documentation page.
const docsUrl = 'https://docs.shorebird.dev';

/// Link to the Flutter version page on the Shorebird documentation.
const flutterVersionUrl = '$docsUrl/getting-started/flutter-version';

/// Link to the supported Flutter versions section on the Shorebird
/// documentation.
const supportedFlutterVersionsUrl =
    '$flutterVersionUrl#supported-flutter-versions';

/// Link to the troubleshooting page on the Shorebird documentation.
const troubleshootingUrl = '$docsUrl/faq';

/// Link to the troubleshooting section which covers the
/// Unsupported class file major version
const unsupportedClassFileVersionUrl =
    '$troubleshootingUrl#unsupported-class-file-major-version-65';

/// Link to the troubleshooting section which covers the
/// not being able to run the app in VS Code after installing Shorebird.
const cannotRunInVSCodeUrl =
    '''$troubleshootingUrl#i-installed-shorebird-and-now-i-cant-run-my-app-in-vs-code''';

/// Extension to convert a string to a CLI link.
extension ToLink on String {
  /// Wraps the string in a link.
  String toLink() => link(uri: Uri.parse(this));
}
