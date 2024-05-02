import 'package:shorebird_cli/src/command_pipeline/command_pipelines.dart';

class GetReleaseVersionStep extends PipelineStep {
  @override
  Future<PipelineContext> run(PipelineContext context) async {
    return context;
  }
}
