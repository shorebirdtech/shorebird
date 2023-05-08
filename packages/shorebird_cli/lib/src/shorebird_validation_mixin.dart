import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

mixin ShorebirdValidationMixin on ShorebirdCommand {
  /// Runs [Validator.validate] on all [validators] and writes issues to stdout.
  Future<List<ValidationIssue>> logAndGetValidationIssues() async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate(process)),
    ))
        .flattened;
    if (validationIssues.isNotEmpty) {
      for (final issue in validationIssues) {
        logger.info(issue.displayMessage);
      }
    }

    return validationIssues.toList();
  }
}
