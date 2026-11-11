import 'package:shorebird_cli/src/commands/patches/patches.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template patches_command}
/// Commands for managing Shorebird patches.
/// {@endtemplate}
class PatchesCommand extends ShorebirdCommand {
  /// {@macro patches_command}
  PatchesCommand() {
    addSubcommand(PatchesInfoCommand());
    addSubcommand(PatchesListCommand());
    addSubcommand(PatchesStatsCommand());
    addSubcommand(PromoteCommand());
    addSubcommand(RollbackCommand());
    addSubcommand(RollforwardCommand());
    addSubcommand(RolloutCommand());
    addSubcommand(SetTrackCommand());
  }

  @override
  String get name => 'patches';

  @override
  String get description =>
      'Manage Shorebird patches.\n\n'
      'A patch replaces the Dart code of a release that is already shipped, so '
      'every subcommand here identifies its patch by the release version it '
      'belongs to and the patch number within that release.\n\n'
      'Examples:\n'
      '  shorebird patches list --release-version 1.0.0+1\n'
      '  shorebird patches info --release-version 1.0.0+1 --patch-number 1\n'
      '  shorebird patches promote --release-version 1.0.0+1 --patch-number 1 '
      '--rollout 10\n'
      '  shorebird patches rollout --release-version 1.0.0+1 --patch-number 1 '
      '--percentage 50';
}
