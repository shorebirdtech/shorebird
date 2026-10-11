import 'dart:io';

import 'package:shorebird_cli/src/logging/logging.dart';

/// Cleanup helpers for temporary [Directory]s.
extension TemporaryDirectory on Directory {
  /// Deletes this directory and everything in it, if it exists.
  ///
  /// Meant for temporary directories the CLI created, deleted from `finally`
  /// blocks once they are no longer needed. A failure is logged rather than
  /// thrown: it must neither mask the error that may already be propagating
  /// nor stop the remaining cleanup from running.
  void deleteTemporarySync() {
    try {
      if (existsSync()) deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      logger.detail('Failed to delete $path: $error');
    }
  }
}
