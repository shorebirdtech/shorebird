import 'package:shorebird_cli/src/command.dart';

/// {@template collaborators_command}
/// `shorebird collaborators`
/// Manage collaborators for a Shorebird app.
/// {@endtemplate}
class CollaboratorsCommand extends ShorebirdCommand {
  /// {@macro collaborators_command}
  CollaboratorsCommand({required super.logger});

  @override
  String get description => 'Manage collaborators for a Shorebird app';

  @override
  String get name => 'collaborators';
}
