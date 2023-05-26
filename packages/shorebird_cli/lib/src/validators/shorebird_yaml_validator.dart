import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class ShorebirdYamlValidator extends Validator {
  ShorebirdYamlValidator();

  @override
  String get description => 'Shorebird is initialized';

  @override
  Future<List<ValidationIssue>> validate(ShorebirdProcess process) async {
    final isShorebirdInitialized = getShorebirdYamlFile().existsSync();

    if (!isShorebirdInitialized) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Shorebird is not initialized.',
        )
      ];
    }

    return [];
  }

  File getShorebirdYamlFile() {
    return File(p.join(Directory.current.path, 'shorebird.yaml'));
  }

  @override
  ValidatorScope get scope => ValidatorScope.installation;
}
