import 'package:shorebird_cli/src/commands/audit_log/audit_log.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template audit_log_command}
/// `shorebird audit-log`
/// Commands for an organization's audit log.
/// {@endtemplate}
class AuditLogCommand extends ShorebirdCommand {
  /// {@macro audit_log_command}
  AuditLogCommand() : _enterpriseRoute = false {
    addSubcommand(AuditLogListCommand());
    addSubcommand(AuditLogExportCommand());
  }

  /// `shorebird enterprise audit-log`: the same subcommands, reading the
  /// enterprise's log.
  AuditLogCommand.enterprise() : _enterpriseRoute = true {
    addSubcommand(AuditLogListCommand(enterpriseRoute: true));
    addSubcommand(AuditLogExportCommand(enterpriseRoute: true));
  }

  final bool _enterpriseRoute;

  @override
  String get name => 'audit-log';

  @override
  List<String> get aliases => const ['audit-logs', 'audit'];

  @override
  String get description => _enterpriseRoute
      ? "Read your enterprise's audit log: its own events, and across its "
            'organizations who is in them, with what access, and changes to '
            'organizations and apps. With no subcommand, shows '
            'one page (the same as `shorebird enterprise audit-log list`). '
            'Needs an owner or admin of the enterprise.'
      : "Read an organization's audit log: who did what. With no subcommand, "
            'shows one page (the same as `shorebird audit-log list`). Needs '
            'a plan that includes the audit log, and the owner, admin or '
            'auditor role.\n\n'
            "For an enterprise's log, run `shorebird enterprise audit-log`.";

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
