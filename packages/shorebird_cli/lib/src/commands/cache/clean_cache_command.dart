import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/cache_pruning.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template clean_cache_command}
/// `shorebird cache clean`
/// Clears the Shorebird cache directory.
/// {@endtemplate}
class CleanCacheCommand extends ShorebirdCommand {
  /// {@macro clean_cache_command}
  CleanCacheCommand() {
    argParser.addFlag(
      unusedFlag,
      negatable: false,
      help:
          'Only remove Flutter versions, engine artifacts and previews not '
          'used in the last ${unusedCacheMaxAge.inDays} days, and previews '
          'beyond the ${Cache.maxCachedPreviews} most recent. Shorebird also '
          'does this automatically on every run.',
    );
  }

  /// Name of the flag that limits cleaning to what has gone unused.
  static const unusedFlag = 'unused';

  @override
  String get description => 'Clears the Shorebird cache directory.';

  @override
  String get name => 'clean';

  @override
  List<String> get aliases => ['clear'];

  @override
  Future<int> run() async {
    if (results[unusedFlag] == true) return _removeUnused();

    final progress = logger.progress('Clearing cache');
    try {
      await cache.clear();
    } on FileSystemException catch (error) {
      final cachePath = Cache.shorebirdCacheDirectory.path;
      progress.fail('''Failed to delete cache directory $cachePath: $error''');

      if (!platform.isWindows) {
        return ExitCode.software.code;
      }

      final superuserLink = link(
        uri: Uri.parse(
          'https://superuser.com/questions/1333118/cant-delete-empty-folder-because-it-is-used',
        ),
      );

      logger.info('''
This could be because a program is using a file in the cache directory. To find and stop such a program, see:
    ${lightCyan.wrap(superuserLink)}
''');
      return ExitCode.software.code;
    }

    progress.complete('Cleared cache');
    return ExitCode.success.code;
  }

  int _removeUnused() {
    final progress = logger.progress('Removing unused cached files');
    final counts = {
      'Flutter version': shorebirdFlutter.pruneUnusedRevisions().length,
      'engine artifact': cache.pruneUnusedArtifacts().length,
      'preview': cache.pruneUnusedPreviews().length,
    };
    final removed = [
      for (final MapEntry(key: noun, value: n) in counts.entries)
        if (n > 0) '$n unused $noun${n == 1 ? '' : 's'}',
    ];
    progress.complete(
      removed.isEmpty
          ? 'Nothing unused to remove'
          : 'Removed ${removed.join(', ')}',
    );
    return ExitCode.success.code;
  }
}
