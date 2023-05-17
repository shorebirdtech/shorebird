import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/collaborators/list_collaborators_command.dart';

/// {@template collaborators_command}
/// `shorebird collaborators`
/// Manage collaborators for a Shorebird app.
/// {@endtemplate}
class CollaboratorsCommand extends ShorebirdCommand {
  /// {@macro collaborators_command}
  CollaboratorsCommand({required super.logger}) {
    addSubcommand(ListCollaboratorsCommand(logger: logger));
  }

  @override
  String get description => 'Manage collaborators for a Shorebird app';

  @override
  String get name => 'collaborators';
}
