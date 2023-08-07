import 'dart:io';

import 'package:shorebird_cli/src/process.dart';

/// A wrapper around all git related functionality.
class Git {
  static const executable = 'git';

  /// Clones the git repository located at [url] into the [outputDirectory].
  /// `git clone <url> ...<args> <outputDirectory>`
  Future<void> clone({
    required String url,
    required String outputDirectory,
    List<String>? args,
  }) async {
    final arguments = [
      'clone',
      url,
      ...?args,
      outputDirectory,
    ];
    final result = await process.run(
      executable,
      arguments,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw ProcessException(
        executable,
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }
}
