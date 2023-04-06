import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template cache_command}
///
/// `shorebird cache`
/// Manage the Shorebird cache.
/// {@endtemplate}
class CacheCommand extends ShorebirdCommand {
  /// {@macro cache_command}
  CacheCommand({required super.logger}) {
    addSubcommand(CleanCacheCommand(logger: logger));
  }

  @override
  String get description => 'Manage the Shorebird cache.';

  @override
  String get name => 'cache';
}
