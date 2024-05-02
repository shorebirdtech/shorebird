import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_pipeline/command_pipelines.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

class ValidateAndroidPreconditionsStep extends PipelineStep {
  @override
  Future<PipelineContext> run(PipelineContext context) async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        validators: doctor.androidCommandValidators,
      );
    } on PreconditionFailedException catch (e) {
      logErrorAndExit(message: null, exitCode: ExitCode.software);
    }

    return context;
  }
}
