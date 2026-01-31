import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:xml/xml.dart';

/// Checks that android/app/src/main/AndroidManifest.xml contains the INTERNET
/// permission, which is required for Shorebird to work.
///
/// See https://github.com/shorebirdtech/shorebird/issues/160.
class AndroidInternetPermissionValidator extends Validator {
  /// Path to the main AndroidManifest.xml file.
  final String _mainAndroidManifestPath = p.join(
    'android',
    'app',
    'src',
    'main',
    'AndroidManifest.xml',
  );

  @override
  String get description =>
      'AndroidManifest.xml files contain INTERNET permission';

  @override
  bool canRunInCurrentContext() => _androidSrcDirectory?.existsSync() ?? false;

  // coverage:ignore-start
  @override
  String get incorrectContextMessage =>
      '''
The ${_androidSrcDirectory?.path ?? 'android/app/src'} directory does not exist.

The command you are running must be run within a Flutter app project that supports the Android platform. If you are releasing a Flutter module, use 'aar' in place of 'android' in your shorebird command.''';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    final manifestFilePath = p.join(
      _androidSrcDirectory!.path,
      'main',
      'AndroidManifest.xml',
    );
    final manifestFile = File(manifestFilePath);
    if (!manifestFile.existsSync()) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: '''No AndroidManifest.xml file found at $manifestFilePath''',
        ),
      ];
    }

    if (!_androidManifestHasInternetPermission(manifestFilePath)) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message:
              '$_mainAndroidManifestPath is missing the INTERNET permission.',
          fix: () => _addInternetPermissionToFile(manifestFilePath),
        ),
      ];
    }

    return [];
  }

  Directory? get _androidSrcDirectory {
    final root = shorebirdEnv.getFlutterProjectRoot();
    if (root == null) return null;
    return Directory(p.join(root.path, 'android', 'app', 'src'));
  }

  bool _androidManifestHasInternetPermission(String path) {
    final xmlDocument = XmlDocument.parse(File(path).readAsStringSync());
    return xmlDocument.rootElement.childElements.any(
      _isInternetPermissionElement,
    );
  }

  bool _isInternetPermissionElement(XmlElement element) {
    if (element.localName != 'uses-permission') {
      return false;
    }

    final attribute = element.attributes.first;
    return attribute.qualifiedName == 'android:name' &&
        attribute.value == 'android.permission.INTERNET';
  }

  void _addInternetPermissionToFile(String path) {
    final file = File(path);
    final contents = file.readAsStringSync();
    // Insert the permission after the opening <manifest> tag to preserve
    // the existing formatting of the file.
    final manifestTagEnd = RegExp('<manifest[^>]*>');
    final match = manifestTagEnd.firstMatch(contents);
    if (match == null) return;
    final indent = _detectIndent(contents);
    final permissionLine =
        '$indent<uses-permission android:name="android.permission.INTERNET"/>';
    final updated = contents.replaceRange(
      match.end,
      match.end,
      '\n$permissionLine',
    );
    file.writeAsStringSync(updated);
  }

  /// Detects the indentation used in the manifest by looking at the first
  /// indented line after the `<manifest>` tag.
  String _detectIndent(String contents) {
    final lines = contents.split('\n');
    for (final line in lines) {
      final stripped = line.trimLeft();
      if (stripped.isEmpty || stripped.startsWith('<manifest')) continue;
      if (line.length != stripped.length) {
        return line.substring(0, line.length - stripped.length);
      }
    }
    return '    ';
  }
}
