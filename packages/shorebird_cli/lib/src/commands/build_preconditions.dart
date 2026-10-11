import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/validators/validators.dart';

/// Checks the preconditions every release and patch shares: the user is
/// logged in and the project is initialized with Shorebird. Also runs the
/// platform's doctor [validators] and, when given, requires the host to be one
/// of [supportedOperatingSystems].
///
/// Exits with the failing check's exit code, by throwing a
/// [PreconditionFailedExit].
Future<void> assertBuildPreconditions({
  List<Validator> validators = const [],
  Set<String>? supportedOperatingSystems,
}) async {
  try {
    await shorebirdValidator.validatePreconditions(
      checkUserIsAuthenticated: true,
      checkShorebirdInitialized: true,
      validators: validators,
      supportedOperatingSystems: supportedOperatingSystems,
    );
  } on PreconditionFailedException catch (e) {
    throw PreconditionFailedExit(e);
  }
}

/// {@template precondition_failed_exit}
/// A [ProcessExit] for a failed precondition, carrying the [failure] so the
/// command runner can report why with `--json` instead of just the exit code.
/// {@endtemplate}
class PreconditionFailedExit extends ProcessExit {
  /// {@macro precondition_failed_exit}
  PreconditionFailedExit(this.failure) : super(failure.exitCode.code);

  /// The precondition that failed.
  final PreconditionFailedException failure;
}

/// Exits with a config error unless pubspec.yaml declares the
/// `androidPackage` that Android archive (aar) releases and patches need.
void assertAndroidPackageNameConfigured() {
  if (shorebirdEnv.androidPackageName == null) {
    logger.err('Could not find androidPackage in pubspec.yaml.');
    throw ProcessExit(ExitCode.config.code);
  }
}
