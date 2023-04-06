import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/validators/shorebird_flutter_validator.dart';

mixin FlutterValidationMixin on ShorebirdCommand {
  /// Runs [ShorebirdFlutterValidator.validate] and writes validation issues to
  /// stdout.
  Future<void> logFlutterValidationIssues() async {
    final flutterValidationIssues = await flutterValidator.validate();
    if (flutterValidationIssues.isNotEmpty) {
      for (final issue in flutterValidationIssues) {
        logger.info(issue.displayMessage);
      }
    }
  }
}
