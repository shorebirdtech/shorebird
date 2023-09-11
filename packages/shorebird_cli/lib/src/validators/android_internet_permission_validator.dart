import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:xml/xml.dart';

/// Checks that all AndroidManifest.xml files in android/app/src/{flavor}/
/// contain the INTERNET permission, which is required for Shorebird to work.
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

  @override
  String get incorrectContextMessage => '''
The ${_androidSrcDirectory.path} directory does not exist.

The command you are running must be run at the root of a Flutter app project that supports the Android platform. If you are releasing a Flutter module, use 'aar' in place of 'android' in your shorebird command.''';

  @override
  Future<List<ValidationIssue>> validate() async {
    const manifestFileName = 'AndroidManifest.xml';

    final manifestFiles = _androidSrcDirectory
        .listSync()
        .whereType<Directory>()
        .where(
          (dir) => dir
              .listSync()
              .whereType<File>()
              .any((file) => p.basename(file.path) == manifestFileName),
        )
        .map((e) => p.join(e.path, manifestFileName));

    if (manifestFiles.isEmpty) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message:
              '''No AndroidManifest.xml files found in ${_androidSrcDirectory.path}''',
        ),
      ];
    }

    final manifestsWithoutInternetPermission = manifestFiles
        .where((manifest) => !_androidManifestHasInternetPermission(manifest));

    if (manifestsWithoutInternetPermission.isNotEmpty) {
      return manifestsWithoutInternetPermission.map(
        (String manifestPath) {
          return ValidationIssue(
            severity: manifestPath.contains(mainAndroidManifestPath)
                ? ValidationIssueSeverity.error
                : ValidationIssueSeverity.warning,
            message:
                '${p.relative(manifestPath, from: Directory.current.path)} '
                'is missing the INTERNET permission.',
            fix: () => _addInternetPermissionToFile(manifestPath),
          );
        },
      ).toList();
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
