import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

mixin ShorebirdValidationMixin on ShorebirdCommand {
  /// Runs [Validator.validate] on all [validators] and writes issues to stdout.
  Future<Map<Validator, List<ValidationIssue>>>
      logAndGetValidationIssues() async {
    final validationIssues = await getValidationIssues();
    logValidationIssues(validationIssues);

    return validationIssues;
  }

  /// Runs [Validator.validate] on all [validators] and returns the number of
  /// critical issues.
  Future<int> logAndGetCriticalIssueCount() async {
    final validationIssues = await logAndGetValidationIssues();
    return validationIssues.values
        .expand((issues) => issues)
        .where((issue) => issue.severity == ValidationIssueSeverity.error)
        .length;
  }

  /// Runs [Validator.validate] on all [validators] and returns a map of
  /// [Validator] to [ValidationIssue]s.
  Future<Map<Validator, List<ValidationIssue>>> getValidationIssues() async {
    final validationIssuesList = await Future.wait(
      validators.map((v) => v.validate(process)),
    );
    return validationIssuesList.asMap().map(
          (index, validationIssues) => MapEntry(
            validators[index],
            validationIssues,
          ),
        );
  }

  /// Writes issues of all [validators] to stdout.
  void logValidationIssues(Map<Validator, List<ValidationIssue>> issues) {
    if (issues.isEmpty) {
      return;
    }

    for (final entry in issues.entries) {
      final issues = entry.value;
      for (final issue in issues) {
        logger.info(issue.displayMessage);
      }
    }
  }
}
