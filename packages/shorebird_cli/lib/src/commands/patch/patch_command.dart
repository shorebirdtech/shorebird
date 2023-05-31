import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template patch_command}
/// `shorebird patch`
/// Create new app release patch.
/// {@endtemplate}
class PatchCommand extends ShorebirdCommand {
  /// {@macro patch_command}
  PatchCommand({required super.logger}) {
    addSubcommand(PatchAndroidCommand(logger: logger));
  }

  @override
  String get description =>
      'Publish new patches for a specific release to Shorebird.';

  @override
  String get name => 'patch';
}
