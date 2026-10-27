import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// Why sessions are managed in the console.
const _accountApiWhy =
    'Sessions are listed and signed out in the console, which the account '
    'API allows only for a signed-in person, not a CLI token.';

/// {@template account_command}
/// Commands for inspecting the current Shorebird account.
/// {@endtemplate}
class AccountCommand extends ShorebirdCommand {
  /// {@macro account_command}
  AccountCommand() {
    addSubcommand(AccountAppsCommand());
    addSubcommand(
      ConsolePageCommand(
        name: 'delete',
        action: 'delete your account',
        path: 'account',
        why:
            'Deleting your account cannot be undone, so a person confirms it '
            'in the console.',
      ),
    );
    addSubcommand(AccountNotificationsCommand());
    addSubcommand(AccountUpdateCommand());
    addSubcommand(OrgsCommand());
    addSubcommand(
      ConsolePageCommand(
        name: 'sessions',
        action: 'see and sign out your sessions',
        path: 'account',
        why: _accountApiWhy,
      ),
    );
    addSubcommand(WhoamiCommand());
  }

  @override
  String get name => 'account';

  @override
  String get description =>
      'Manage your Shorebird account. With no subcommand, shows who you are '
      '(the same as `shorebird account whoami`).';

  @override
  String get defaultSubcommand => 'whoami';
}
