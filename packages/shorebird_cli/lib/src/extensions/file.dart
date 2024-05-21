import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/io.dart';

/// Extension methods for validating [File]s.
extension FileValidations on File {
  /// Logs an error and exits with [ExitCode.usage] if this file does not exist.
  void assertExists() {
    if (!existsSync()) {
      logger.err(
        'No file found at $path',
      );
      exit(ExitCode.usage.code);
    }
  }
}
