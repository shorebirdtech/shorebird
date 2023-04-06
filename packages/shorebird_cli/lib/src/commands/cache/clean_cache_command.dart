import 'dart:async';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_engine_mixin.dart';

/// {@template clean_cache_command}
///
/// `shorebird cache clean`
/// Deletes Shorebird's cached data when using the CLI.
/// {@endtemplate}
class CleanCacheCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdEngineMixin {
  /// {@macro clean_cache_command}
  CleanCacheCommand({
    required super.logger,
  });

  @override
  String get description =>
      "Deletes Shorebird's cached data when using the CLI.";

  @override
  String get name => 'clean';

  @override
  Future<int>? run() async {
    final enginesDirectory = Directory(p.normalize('$shorebirdEnginePath/../'));
    print(enginesDirectory.path);

    if (!enginesDirectory.existsSync()) {
      logger.info('The cache is already clean.');
      return ExitCode.success.code;
    }

    try {
      enginesDirectory.deleteSync(recursive: true);
    } catch (err) {
      logger.err('Could not clean cache: $err');
      return ExitCode.ioError.code;
    }

    logger.success('Successfully cleaned the cache!');
    return ExitCode.success.code;
  }
}
