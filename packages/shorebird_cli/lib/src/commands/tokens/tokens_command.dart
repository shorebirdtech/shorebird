import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/account_list_command.dart';
import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// Why API keys are managed in the console.
const _why =
    'API keys act as you, so they are made and revoked in the console, '
    'which the account API allows only for a signed-in person, not a CLI '
    'token. `shorebird tokens list` lists them here.';

/// {@template tokens_command}
/// `shorebird tokens`
/// Opens the console page that lists, creates and deletes API keys (the
/// tokens set as SHOREBIRD_TOKEN).
/// {@endtemplate}
class TokensCommand extends ShorebirdCommand {
  /// {@macro tokens_command}
  TokensCommand() {
    for (final (name, action, aliases) in [
      ('create', 'create an API key', const <String>[]),
      ('delete', 'delete an API key', const ['revoke']),
    ]) {
      addSubcommand(
        ConsolePageCommand(
          name: name,
          action: action,
          path: 'account/api-keys',
          why: _why,
          aliases: aliases,
        ),
      );
    }
    addSubcommand(
      AccountListCommand(
        name: 'list',
        commandLine: 'shorebird tokens list',
        lead:
            'List your API keys: id, name, created, last used and expires '
            '(UTC dates). Never prints a key itself.',
        apiPath: 'api/api-keys',
        listKey: 'api_keys',
        consolePath: 'account/api-keys',
        action: 'see your API keys',
        manage: 'Create or revoke a key',
        none: 'No API keys.',
        describe: (key) =>
            '${key['id']}  ${lightCyan.wrap('${key['name']}')}  '
            'created ${accountListDate(key['created_at'])}  '
            'last used ${accountListDate(key['last_used_at'])}  '
            'expires ${accountListDate(key['expires_at'])}',
      ),
    );
  }

  @override
  String get name => 'tokens';

  @override
  List<String> get aliases => const ['api-keys', 'token'];

  @override
  String get description =>
      'Manage your API keys (the tokens you set as SHOREBIRD_TOKEN in CI). '
      '`list` prints them; `create` and `delete` open the Shorebird console, '
      'where keys are made and revoked. With no subcommand, the same as '
      '`shorebird tokens list`.';

  @override
  String get defaultSubcommand => 'list';
}
