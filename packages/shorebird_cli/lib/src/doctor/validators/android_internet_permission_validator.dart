import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/doctor/doctor_validator.dart';
import 'package:xml/xml.dart';

class AndroidInternetPermissionValidator extends DoctorValidator {
  @override
  String get description =>
      'AndroidManifest.xml files contain INTERNET permission';

  @override
  Future<List<ValidationIssue>> validate() async {
    const manifestFileName = 'AndroidManifest.xml';
    final androidSrcDir = Directory(
      p.join(
        Directory.current.path,
        'android',
        'app',
        'src',
      ),
    );
    final manifestsWithoutInternetPermission = androidSrcDir
        .listSync()
        .whereType<Directory>()
        .where((dir) {
          return dir.listSync().whereType<File>().any(
                (file) => p.basename(file.path) == 'AndroidManifest.xml',
              );
        })
        .map((e) => p.join(e.path, manifestFileName))
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
