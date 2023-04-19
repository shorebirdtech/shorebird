import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:xml/xml.dart';

/// Checks that all AndroidManifest.xml files in android/app/src/{flavor}/
/// contain the INTERNET permission, which is required for Shorebird to work.
///
/// See https://github.com/shorebirdtech/shorebird/issues/160.
class AndroidInternetPermissionValidator extends Validator {
  // coverage:ignore-start
  @override
  String get description =>
      'AndroidManifest.xml files contain INTERNET permission';
  // coverage:ignore-end

  @override
  Future<List<ValidationIssue>> validate(ShorebirdProcess process) async {
    const manifestFileName = 'AndroidManifest.xml';
    final androidSrcDir = Directory(
      p.join(
        Directory.current.path,
        'android',
        'app',
        'src',
      ),
    );

    if (!androidSrcDir.existsSync()) {
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
              .any((file) => p.basename(file.path) == 'AndroidManifest.xml'),
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
      return manifestsWithoutInternetPermission
          .map(
            (String manifestPath) => ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message: '$manifestPath is missing the INTERNET permission.',
            ),
          )
          .toList();
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
}
