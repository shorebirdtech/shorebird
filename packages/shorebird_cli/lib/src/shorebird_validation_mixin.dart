import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

mixin ShorebirdValidationMixin on ShorebirdCommand {
  /// Runs [Validator.validate] on all [validators] and writes results to
  /// stdout.
  Future<List<ValidationIssue>> runValidators() async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate(process)),
    ))
        .flattened
        .toList();

    for (final issue in validationIssues) {
      logger.info(issue.displayMessage);
    }

    return validationIssues;
  }

  /// Whether any [ValidationIssue]s have a severity of
  /// [ValidationIssueSeverity.error].
  bool validationIssuesContainsError(List<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.error);

  /// Logs a message indicating that validation failed. If any of the issues
  /// can be automatically fixed, this also prompts the user to run
  /// `shorebird doctor --fix`.
  void logValidationFailure({required List<ValidationIssue> issues}) {
    logger.err('Aborting due to validation errors.');

    final fixableIssues = issues.where((issue) => issue.fix != null);
    if (fixableIssues.isNotEmpty) {
      logger.info(
        '''${fixableIssues.length} issue${fixableIssues.length == 1 ? '' : 's'} can be fixed automatically with ${lightCyan.wrap('shorebird doctor --fix')}.''',
      );
    }
  }
}
