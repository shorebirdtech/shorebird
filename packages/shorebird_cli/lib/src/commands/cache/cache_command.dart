import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template cache_command}
/// `shorebird cache`
/// Manage the Shorebird cache.
/// {@endtemplate}
class CacheCommand extends ShorebirdCommand {
  /// {@macro cache_command}
  CacheCommand() {
    addSubcommand(CleanCacheCommand());
  }

  @override
  String get description => 'Manage the Shorebird cache.';

  @override
  String get name => 'cache';
}
