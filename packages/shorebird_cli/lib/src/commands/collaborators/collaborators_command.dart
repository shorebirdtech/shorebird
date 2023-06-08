import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/commands.dart';

/// {@template collaborators_command}
/// `shorebird collaborators`
/// Manage collaborators for a Shorebird app.
/// {@endtemplate}
class CollaboratorsCommand extends ShorebirdCommand {
  /// {@macro collaborators_command}
  CollaboratorsCommand() {
    addSubcommand(AddCollaboratorsCommand());
    addSubcommand(DeleteCollaboratorsCommand());
    addSubcommand(ListCollaboratorsCommand());
  }

  @override
  String get description => 'Manage collaborators for a Shorebird app';

  @override
  String get name => 'collaborators';
}
