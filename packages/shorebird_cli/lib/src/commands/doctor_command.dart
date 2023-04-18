import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
import 'package:shorebird_cli/src/shorebird_version_mixin.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:shorebird_cli/src/version.dart';

/// {@template doctor_command}
///
/// `shorebird doctor`
/// A command that checks for potential issues with the current shorebird
/// environment.
/// {@endtemplate}
class DoctorCommand extends ShorebirdCommand with ShorebirdVersionMixin {
  /// {@macro doctor_command}
  DoctorCommand({
    required super.logger,
    super.validators,
  }) {
    validators = _allValidators(baseValidators: validators);
  }

  late final List<Validator> _doctorValidators = [
    ShorebirdVersionValidator(
      isShorebirdVersionCurrent: isShorebirdVersionCurrent,
    ),
    ShorebirdFlutterValidator(),
    AndroidInternetPermissionValidator(),
  ];

  @override
  String get name => 'doctor';

  @override
  String get description => 'Show information about the installed tooling.';

  @override
  Future<int> run() async {
    logger.info('''

Shorebird v$packageVersion
Shorebird Engine • revision ${ShorebirdEnvironment.shorebirdEngineRevision}''');

    var numIssues = 0;
    for (final validator in validators) {
      final progress = logger.progress(validator.description);
      final issues = await validator.validate(process);
      numIssues += issues.length;
      if (issues.isEmpty) {
        progress.complete();
      } else {
        progress.fail();

        for (final issue in issues) {
          logger.info('  ${issue.displayMessage}');
        }
      }
    }

    logger.info('');

    if (numIssues == 0) {
      logger.info('No issues detected!');
    } else {
      logger.info('$numIssues issue${numIssues == 1 ? '' : 's'} detected.');
    }

    return ExitCode.success.code;
  }

  /// Creates a list that is the union of [baseValidators] and
  /// [_doctorValidators].
  List<Validator> _allValidators({
    required List<Validator> baseValidators,
  }) {
    final missingValidators = _doctorValidators
        .where(
          (doctorValidator) => baseValidators.none(
            (baseValidator) => baseValidator.id == doctorValidator.id,
          ),
        )
        .toList();

    return baseValidators + missingValidators;
  }
}
