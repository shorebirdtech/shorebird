import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template clean_cache_command}
///
/// `shorebird cache clean`
/// Deletes Shorebird's cached data when using the CLI.
/// {@endtemplate}
class CleanCacheCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro clean_cache_command}
  CleanCacheCommand({required super.logger});

  @override
  String get description =>
      "Deletes Shorebird's cached data when using the CLI.";

  @override
  String get name => 'clean';

  @override
  Future<int>? run() async {
    final cacheDirectory = Cache.shorebirdCacheDirectory;

    if (!cacheDirectory.existsSync()) {
      logger.info('The cache is already clean.');
      return ExitCode.success.code;
    }

    try {
      cacheDirectory.deleteSync(recursive: true);
    } catch (err) {
      logger.err('Could not clean cache: $err');
      return ExitCode.ioError.code;
    }

    logger.success('Successfully cleaned the cache!');
    return ExitCode.success.code;
  }
}
