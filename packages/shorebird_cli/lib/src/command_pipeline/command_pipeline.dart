import 'package:shorebird_cli/src/command_pipeline/command_pipelines.dart';

class CommandPipeline {
  CommandPipeline({
    required this.steps,
    PipelineContext? context,
  }) : context = context ?? PipelineContext({});

  final PipelineContext context;
  final List<PipelineStep> steps;

  Future<void> run() async {
    var context = PipelineContext({});
    for (final step in steps) {
      context = await step.run(context);
    }
  }
}
