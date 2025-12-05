import 'package:shorebird_cli/src/commands/patches/patches.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template patches_command}
/// Commands for managing Shorebird patches.
/// {@endtemplate}
class PatchesCommand extends ShorebirdCommand {
  /// {@macro patches_command}
  PatchesCommand() {
    addSubcommand(PromoteCommand());
    addSubcommand(SetChannelCommand());
  }

  @override
  String get name => 'patches';

  @override
  String get description => 'Manage Shorebird patches';
}
