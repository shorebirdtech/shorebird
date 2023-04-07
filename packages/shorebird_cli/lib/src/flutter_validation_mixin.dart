import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/validators/shorebird_flutter_validator.dart';

mixin FlutterValidationMixin on ShorebirdCommand {
  /// Runs [ShorebirdFlutterValidator.validate] and writes validation issues to
  /// stdout.
  Future<void> logValidationIssues() async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate()),
    ))
        .flattened;
    if (validationIssues.isNotEmpty) {
      for (final issue in validationIssues) {
        logger.info(issue.displayMessage);
      }
    }
  }
}
