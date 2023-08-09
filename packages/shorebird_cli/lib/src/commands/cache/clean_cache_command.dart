import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';

/// {@template clean_cache_command}
/// `shorebird cache clean`
/// Clears the Shorebird cache directory.
/// {@endtemplate}
class CleanCacheCommand extends ShorebirdCommand {
  /// {@macro clean_cache_command}
  CleanCacheCommand();

  @override
  String get description => 'Clears the Shorebird cache directory.';

  @override
  String get name => 'clean';

  @override
  List<String> get aliases => ['clear'];

  @override
  Future<int> run() async {
    final progress = logger.progress('Clearing Cache');
    try {
      cache.clear();
    } on FileSystemException catch (error) {
      final cachePath = Cache.shorebirdCacheDirectory.path;
      progress.fail(
        '''Failed to delete cache directory $cachePath: $error''',
      );
      if (!platform.isWindows) {
        return ExitCode.software.code;
      }

      final superuserLink = link(
        uri: Uri.parse(
          'https://superuser.com/questions/1333118/cant-delete-empty-folder-because-it-is-used',
        ),
      );

      logger.info(
        '''
This could be because a program is using a file in the cache directory. To find and stop such a program, see:
    ${lightCyan.wrap(superuserLink)}
''',
      );
      return ExitCode.software.code;
    }

    progress.complete('Cleared cache');
    return ExitCode.success.code;
  }
}
