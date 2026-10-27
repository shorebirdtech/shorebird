import 'package:shorebird_cli/src/commands/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template audit_log_command}
/// `shorebird audit-log`
/// Commands for an organization's audit log.
/// {@endtemplate}
class AuditLogCommand extends ShorebirdCommand {
  /// {@macro audit_log_command}
  AuditLogCommand() {
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
      'shows one page (the same as `shorebird audit-log list`). Needs '
      'a plan that includes the audit log, and the owner, admin or auditor '
      'role.';

  @override
  String get defaultSubcommand => 'list';
}

/// {@template orgs_audit_log_command}
/// `shorebird orgs audit-log`, a hidden alias of `shorebird audit-log`, for
/// agents that look under the organization noun.
/// {@endtemplate}
class OrgsAuditLogCommand extends AuditLogCommand {
  /// {@macro orgs_audit_log_command}
  OrgsAuditLogCommand();

  @override
  bool get hidden => true;
}
