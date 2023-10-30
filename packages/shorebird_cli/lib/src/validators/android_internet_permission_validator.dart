import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:xml/xml.dart';

/// Checks that android/app/src/main/AndroidManifest.xml contains the INTERNET
/// permission, which is required for Shorebird to work.
///
/// See https://github.com/shorebirdtech/shorebird/issues/160.
class AndroidInternetPermissionValidator extends Validator {
  final String mainAndroidManifestPath = p.join(
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
  bool canRunInCurrentContext() => _androidSrcDirectory.existsSync();

  // coverage:ignore-start
  @override
  String get incorrectContextMessage => '''
The ${_androidSrcDirectory.path} directory does not exist.

The command you are running must be run at the root of a Flutter app project that supports the Android platform. If you are releasing a Flutter module, use 'aar' in place of 'android' in your shorebird command.''';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate() async {
    final manifestFilePath = p.join(
      _androidSrcDirectory.path,
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
              '$mainAndroidManifestPath is missing the INTERNET permission.',
          fix: () => _addInternetPermissionToFile(manifestFilePath),
        ),
      ];
    }

    return [];
  }

  Directory get _androidSrcDirectory => Directory(
        p.join(
          Directory.current.path,
          'android',
          'app',
          'src',
        ),
      );

  bool _androidManifestHasInternetPermission(String path) {
    final xmlDocument = XmlDocument.parse(File(path).readAsStringSync());
    return xmlDocument.rootElement.childElements
        .any(_isInternetPermissionElement);
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
    final xmlDocument = XmlDocument.parse(File(path).readAsStringSync());
    xmlDocument.rootElement.children.add(
      XmlElement(
        XmlName('uses-permission'),
        [
          XmlAttribute(
            XmlName('android:name'),
            'android.permission.INTERNET',
          ),
        ],
      ),
    );
    File(path).writeAsStringSync(xmlDocument.toXmlString(pretty: true));
  }
}
