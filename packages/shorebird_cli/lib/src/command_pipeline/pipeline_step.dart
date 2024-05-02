import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command_pipeline/pipeline_context.dart';
import 'package:shorebird_cli/src/logger.dart';

/// {@template pipeline_step}
/// A step in a [Pipeline].
/// {@endtemplate}
abstract class PipelineStep {
  Future<PipelineContext> run(PipelineContext context);

  void logErrorAndExit({required String? message, required ExitCode exitCode}) {
    if (message != null) logger.err(message);
    exit(exitCode.code);
  }
}
