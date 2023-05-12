import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

class ShorebirdYamlValidator extends Validator {
  ShorebirdYamlValidator({required this.hasShorebirdYaml});
  // Adding as Function
  /// Returns true if the project has a shorebird.yaml file.
  final bool Function() hasShorebirdYaml;

  @override
  String get description => 'Shorebird is initialized';

  @override
  Future<List<ValidationIssue>> validate(ShorebirdProcess process) async {
    final isShorebirdInitialized = hasShorebirdYaml.call();

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
}
