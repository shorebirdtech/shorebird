import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
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
      logger.info(
        yellow.wrap('\n!!! Potential issues found !!!\n'),
      );

      for (final issue in validationIssues) {
        logger.info(issue.displayMessage);
      }
      logger.info(
        yellow.wrap(
          '\nThese may cause serious issues with shorebird functionality if '
          'not addressed.\n',
        ),
      );
    }
  }
}
