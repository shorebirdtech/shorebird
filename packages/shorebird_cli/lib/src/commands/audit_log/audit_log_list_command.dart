import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/commands/audit_log/audit_log_filters.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template audit_log_list_command}
/// `shorebird audit-log list`
/// Show one page of an organization's audit log.
/// {@endtemplate}
class AuditLogListCommand extends ShorebirdCommand
    with OrganizationScopedCommand, AuditLogFilterOptions {
  /// {@macro audit_log_list_command}
  AuditLogListCommand() {
    addFilterOptions();
    argParser
      ..addOption('limit', help: 'Entries on the page, 1 to 100 (default 30).')
      ..addOption(
        'cursor',
        help: 'Show this page: the cursor an earlier run printed.',
      );
  }

  @override
  String get name => 'list';

  // The org id, as in `shorebird audit-log 42`.
  @override
  bool get takesPositionalArguments => true;

  @override
  String get invocation => 'shorebird audit-log list [<org-id>]';

  @override
  String get description =>
      "Shows one page of an organization's audit log, newest first.\n\n"
      'Example output (time  event  actor  resources):\n'
      '  2026-10-20 14:03:22Z  organization.rename  alice@acme.com (id: 12)  '
      'organization:42\n\n'
      'For every page, as OCSF events, run '
      '`shorebird audit-log export`.\n\n'
      '${ShorebirdCommand.jsonHint('shorebird audit-log 42 --json')}';

  @override
  Future<int> run() async {
    final limitArg = results['limit'] as String?;
    final limit = limitArg == null ? null : int.tryParse(limitArg);
    if (limitArg != null && (limit == null || limit < 1 || limit > 100)) {
      return reportError(
        message: '--limit must be a number from 1 to 100 (got "$limitArg").',
      );
    }
    final (:filters, :error) = parseFilters();
    if (error != null) return reportError(message: error);

    final (:membership, :errorCode) = await resolveOrganizationFromArguments(
      example: 'shorebird audit-log list <org-id>',
    );
    if (errorCode != null) return errorCode;
    final organizationId = membership!.organization.id;

    late final GetOrganizationAuditLogsResponse page;
    final fetchError = await guardFetch(
      () async => page = await fetchPage(
        organizationId,
        filters!,
        perPage: limit,
        cursor: results['cursor'] as String?,
      ),
      organizationId: organizationId,
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organizationId,
        'entries': [for (final entry in page.data) entry.toJson()],
        'next_cursor': page.nextCursor,
      });
      return ExitCode.success.code;
    }

    if (page.data.isEmpty) logger.info('No audit log entries.');
    for (final entry in page.data) {
      logger.info(_describe(entry));
    }
    // Oldest first always carries a cursor, so only an empty page there
    // means there is nothing more yet.
    if (page.nextCursor case final cursor? when page.data.isNotEmpty) {
      final next = commandFrom(
        'list',
        organizationId: organizationId,
        cursor: cursor,
        extra: [if (limit != null) '--limit $limit'],
      );
      logger.info('Next page: $next');
    }
    return ExitCode.success.code;
  }
}

/// One entry on one line: time, event, actor, and what it acted on.
String _describe(AuditLogEvent entry) {
  final time = DateTime.fromMillisecondsSinceEpoch(
    entry.time,
    isUtc: true,
  ).toIso8601String().substring(0, 19).replaceFirst('T', ' ');
  final user = entry.actor.user;
  final String actor;
  if (user.type == AuditLogActorUserType.shorebirdStaff) {
    actor = 'Shorebird staff';
  } else {
    final label = user.emailAddr ?? user.name ?? 'unknown';
    actor = user.uid == null ? label : '$label (id: ${user.uid})';
  }
  final resources = entry.resources.map((r) => '${r.type}:${r.uid}');
  return [
    '${time}Z',
    lightCyan.wrap(entry.api.operation),
    actor,
    if (resources.isNotEmpty) resources.join(', '),
  ].join('  ');
}
