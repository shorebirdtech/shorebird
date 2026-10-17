import 'package:shorebird_cli/src/commands/invitations/invitations.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template invitations_command}
/// `shorebird invitations`
/// Commands for the invitations sent to you.
/// {@endtemplate}
class InvitationsCommand extends ShorebirdCommand {
  /// {@macro invitations_command}
  InvitationsCommand() {
    addSubcommand(InvitationsListCommand());
    addSubcommand(InvitationsAcceptCommand());
    addSubcommand(InvitationsDeclineCommand());
  }

  @override
  String get name => 'invitations';

  @override
  String get description =>
      'List, accept and decline the invitations sent to you.';
}
