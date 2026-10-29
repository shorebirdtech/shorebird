import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template enterprise_command}
/// `shorebird enterprise`
/// Commands for the enterprise you belong to.
/// {@endtemplate}
class EnterpriseCommand extends ShorebirdCommand {
  /// {@macro enterprise_command}
  EnterpriseCommand() {
    addSubcommand(EnterpriseGetCommand());
  }

  @override
  String get name => 'enterprise';

  @override
  List<String> get aliases => const ['enterprises'];

  @override
  String get description =>
      'Show the enterprise you belong to. With no subcommand, shows it (the '
      'same as `shorebird enterprise get`).\n\n'
      'An enterprise holds several organizations. To act on all of them, '
      'pass --enterprise to `orgs list`, `apps list`, `members`, '
      '`audit-log`, `usage` or `service-accounts list`.';

  @override
  String get defaultSubcommand => 'get';
}
