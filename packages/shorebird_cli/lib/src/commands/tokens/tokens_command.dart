import 'package:shorebird_cli/src/commands/console_page_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// Why API keys are managed in the console.
const _why =
    'API keys act as you, so they are made and revoked in the console, '
    'which the account API allows only for a signed-in person, not a CLI '
    'token.';

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
      ('list', 'see your API keys', const <String>[]),
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
  }

  @override
  String get name => 'tokens';

  @override
  List<String> get aliases => const ['api-keys', 'token'];

  @override
  String get description =>
      'Manage your API keys (the tokens you set as SHOREBIRD_TOKEN in CI). '
      'Each subcommand opens the Shorebird console, where keys are made and '
      'revoked. With no subcommand, the same as `shorebird tokens list`.';

  @override
  String get defaultSubcommand => 'list';
}
