import 'package:shorebird_cli/src/commands/orgs/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template orgs_audit_log_command}
/// `shorebird orgs audit-log`
/// Commands for an organization's audit log.
/// {@endtemplate}
class OrgsAuditLogCommand extends ShorebirdCommand {
  /// {@macro orgs_audit_log_command}
  OrgsAuditLogCommand() {
    addSubcommand(AuditLogListCommand());
    addSubcommand(AuditLogExportCommand());
  }

  @override
  String get name => 'audit-log';

  @override
  List<String> get aliases => const ['audit-logs', 'audit'];

  @override
  String get description =>
      "Read an organization's audit log: who did what. With no subcommand, "
      'shows one page (the same as `shorebird orgs audit-log list`). Needs '
      'a plan that includes the audit log, and the owner, admin or auditor '
      'role.';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template top_level_audit_log_command}
/// `shorebird audit-log`, a hidden alias of `shorebird orgs audit-log`, which
/// agents type first.
/// {@endtemplate}
class TopLevelAuditLogCommand extends OrgsAuditLogCommand {
  /// {@macro top_level_audit_log_command}
  TopLevelAuditLogCommand();

  @override
  bool get hidden => true;
}
