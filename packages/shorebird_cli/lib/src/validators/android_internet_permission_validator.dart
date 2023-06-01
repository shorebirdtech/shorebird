import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_process.dart';
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

  // coverage:ignore-start
  @override
  String get description =>
      'AndroidManifest.xml files contain INTERNET permission';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate(ShorebirdProcess process) async {
    const manifestFileName = 'AndroidManifest.xml';
    final androidSrcDir = [
      p.join(
        Directory.current.path,
        'android',
        'app',
        'src',
      ),
      p.join(
        Directory.current.path,
        '.android',
        'Flutter',
        'src',
      ),
    ].map(Directory.new).firstWhereOrNull((dir) => dir.existsSync());

    if (androidSrcDir == null) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'No Android project found',
        ),
      ];
    }

    final manifestFiles = androidSrcDir
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
              'No AndroidManifest.xml files found in ${androidSrcDir.path}',
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
