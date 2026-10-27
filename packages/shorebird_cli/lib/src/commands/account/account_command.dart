import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/account/account.dart';
import 'package:shorebird_cli/src/commands/account_list_command.dart';
import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:shorebird_cli/src/commands/orgs/orgs.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

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
    addSubcommand(UsageCommand());
    addSubcommand(AccountOrgsCommand());
    addSubcommand(
      AccountListCommand(
        name: 'sessions',
        commandLine: 'shorebird account sessions',
        lead:
            'List the sessions signed in to your account: id, name, IP '
            'address, user agent and last used (UTC date). The session this '
            'CLI is signed in with is marked "(current)".',
        apiPath: 'api/sessions',
        listKey: 'sessions',
        consolePath: 'account',
        action: 'see and sign out your sessions',
        manage: 'Sign out a session',
        none: 'No sessions.',
        describe: (session) => [
          '${session['id']}',
          lightCyan.wrap('${session['name'] ?? 'Unnamed session'}')!,
          ?session['ip_address'] as String?,
          ?session['user_agent'] as String?,
          'last used ${accountListDate(session['last_used_at'])}',
          if (session['is_current'] == true) '(current)',
        ].join('  '),
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
