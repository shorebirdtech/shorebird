import 'dart:io';

import 'package:cli_io/cli_io.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';

/// Extension methods for validating [File]s.
extension FileValidations on File {
  /// Logs an error and exits with [ExitCode.usage] if this file does not exist.
  void assertExists() {
    if (!existsSync()) {
      logger.err('No file found at $path');
      throw ProcessExit(ExitCode.usage.code);
    }
  }
}
