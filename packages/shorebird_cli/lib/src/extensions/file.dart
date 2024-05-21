import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';

/// Extension methods for validating [File]s.
extension FileValidations on File {
  /// Asserts that the file exists.
  ///
  /// When it doesn't, logs an error and exits with [ExitCode.usage].
  void assertExists() {
    if (!existsSync()) {
      logger.err(
        'No file found at $path',
      );
      exit(ExitCode.usage.code);
    }
  }
}
