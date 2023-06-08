import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';

/// {@template clean_cache_command}
/// `shorebird cache clean`
/// Clears the Shorebird cache directory.
/// {@endtemplate}
class CleanCacheCommand extends ShorebirdCommand with ShorebirdConfigMixin {
  /// {@macro clean_cache_command}
  CleanCacheCommand({required super.cache});

  @override
  String get description => 'Clears the Shorebird cache directory.';

  @override
  String get name => 'clean';

  @override
  List<String> get aliases => ['clear'];

  @override
  Future<int> run() async {
    cache.clear();
    logger.success('✅ Cleared Cache!');
    return ExitCode.success.code;
  }
}
