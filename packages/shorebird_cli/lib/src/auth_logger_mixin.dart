import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';

mixin AuthLoggerMixin on ShorebirdCommand {
  void printNeedsAuthInstructions() {
    logger
      ..err('You must be logged in to run this command.')
      ..info(
        '''If you already have an account, run ${lightCyan.wrap('shorebird login')} to sign in.''',
      )
      ..info(
        '''If you don't have a Shorebird account, run ${lightCyan.wrap('shorebird account create')} to create one.''',
      );
  }
}
