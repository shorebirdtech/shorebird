import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_pipeline/command_pipelines.dart';

class ValidateAndroidArgsStep extends PipelineStep {
  @override
  Future<PipelineContext> run(PipelineContext context) async {
    final argResults = context.read<ArgResults>();
    final generateApk = argResults['android-artifact'] as String == 'apk';
    final splitApk = argResults['split-per-abi'] == true;

    if (generateApk && splitApk) {
      logErrorAndExit(
        exitCode: ExitCode.unavailable,
        message: '''
Shorebird does not support the split-per-abi option at this time.
            
Split APKs are each given a different release version than what is specified in the pubspec.yaml.

See ${link(uri: Uri.parse('https://github.com/flutter/flutter/issues/39817'))} for more information about this issue.
Please comment and upvote ${link(uri: Uri.parse('https://github.com/shorebirdtech/shorebird/issues/1141'))} if you would like shorebird to support this.''',
      );
    }

    return context;
  }
}
