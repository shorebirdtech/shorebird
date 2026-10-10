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
/// Exits with the failing check's exit code.
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
    throw ProcessExit(e.exitCode.code);
  }
}

/// Exits with a config error unless pubspec.yaml declares the
/// `androidPackage` that Android archive (aar) releases and patches need.
void assertAndroidPackageNameConfigured() {
  if (shorebirdEnv.androidPackageName == null) {
    logger.err('Could not find androidPackage in pubspec.yaml.');
    throw ProcessExit(ExitCode.config.code);
  }
}
