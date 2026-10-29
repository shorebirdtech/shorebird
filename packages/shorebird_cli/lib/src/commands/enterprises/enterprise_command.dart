import 'package:shorebird_cli/src/commands/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprises.dart';
import 'package:shorebird_cli/src/commands/usage_command.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template enterprise_command}
/// `shorebird enterprise`
/// Commands for the enterprise you belong to, across every organization in
/// it.
/// {@endtemplate}
class EnterpriseCommand extends ShorebirdCommand {
  /// {@macro enterprise_command}
  EnterpriseCommand() {
    addSubcommand(EnterpriseGetCommand());
    addSubcommand(EnterpriseMembersCommand());
    addSubcommand(EnterpriseGuestsCommand());
    addSubcommand(EnterpriseOrgsCommand());
    addSubcommand(EnterpriseAppsCommand());
    addSubcommand(AuditLogCommand.enterprise());
    addSubcommand(UsageCommand(enterpriseRoute: true));
    addSubcommand(EnterpriseServiceAccountsCommand());
  }

  @override
  String get name => 'enterprise';

  @override
  List<String> get aliases => const ['enterprises'];

  @override
  String get description =>
      'Act on the enterprise you belong to, across every organization in '
      'it. With no subcommand, shows the enterprise and your role (the same '
      'as `shorebird enterprise get`).\n\n'
      'Examples:\n'
      '  shorebird enterprise members list\n'
      '  shorebird enterprise members set-role bob@acme.com --role admin\n'
      '  shorebird enterprise guests\n'
      '  shorebird enterprise orgs list\n'
      '  shorebird enterprise apps list\n'
      '  shorebird enterprise audit-log --start 2026-10-21\n'
      '  shorebird enterprise usage\n'
      '  shorebird enterprise service-accounts list';

  @override
  String get defaultSubcommand => 'get';
}
