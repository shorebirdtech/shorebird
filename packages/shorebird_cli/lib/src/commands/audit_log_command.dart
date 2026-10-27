import 'dart:convert';
import 'dart:io' as io;

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// What to do next after the audit log API refused a request with
/// [apiCode], or null when the server's own message says enough.
String? auditLogErrorHint(String? apiCode) => switch (apiCode) {
  'shorebird_plan_insufficient_tier' =>
    'The audit log is part of the Enterprise plan. See '
        'https://shorebird.dev/pricing.',
  _ => null,
};

/// {@template audit_log_command}
/// `shorebird audit-log [export]`
/// Read an organization's audit log: one page, or every page with `export`.
/// {@endtemplate}
class AuditLogCommand extends ShorebirdCommand with OrganizationScopedCommand {
  /// {@macro audit_log_command}
  AuditLogCommand() {
    addOrganizationScopeOption();
    argParser
      ..addOption('app-id', help: 'Only entries about this app.')
      ..addOption(
        'actor',
        help:
            'Only entries this user or service account caused, by id (e.g. '
            '"123"). Each entry shows its actor\'s id.',
      )
      ..addOption(
        'event',
        aliases: const ['operation'],
        help: 'Only entries of this event (e.g. "organization.rename").',
      )
      ..addOption(
        'start',
        aliases: const ['since'],
        help:
            'Only entries at or after this time: a date (2026-10-01, UTC) or '
            'an ISO 8601 time (2026-10-01T09:00:00Z).',
      )
      ..addOption(
        'end',
        aliases: const ['until'],
        help:
            'Only entries at or before this time. A date means the end of '
            'that day, UTC.',
      )
      ..addOption(
        'order',
        allowed: const ['desc', 'asc'],
        defaultsTo: 'desc',
        allowedHelp: const {'desc': 'Newest first.', 'asc': 'Oldest first.'},
      )
      ..addOption(
        'limit',
        help: 'Entries on the page, 1 to 100 (default 30). Not for export.',
      )
      ..addOption(
        'cursor',
        help: 'Start at this page: the cursor an earlier run printed.',
      )
      ..addOption(
        'format',
        allowed: const ['json', 'jsonl'],
        defaultsTo: 'json',
        allowedHelp: const {
          'json': 'One JSON array.',
          'jsonl': 'One entry per line.',
        },
        help: 'How export writes entries.',
      );
  }

  @override
  String get name => 'audit-log';

  @override
  List<String> get aliases => const ['audit-logs', 'audit'];

  @override
  String get invocation => 'shorebird audit-log [export] [arguments]';

  @override
  String get description =>
      "Shows an organization's audit log: who did what, newest first. "
      'Needs the Enterprise plan and the owner, admin or auditor role.\n\n'
      'Example output (time  event  actor  resources):\n'
      '  2026-10-20 14:03:22Z  organization.rename  alice@acme.com (id: 12)  '
      'organization:42\n\n'
      '`shorebird audit-log` shows one page. `shorebird audit-log export` '
      'writes every page to stdout as OCSF API Activity events, to load into '
      'a security log tool:\n'
      '  shorebird audit-log export --start 2026-10-01 > audit.json\n\n'
      '${ShorebirdCommand.jsonHint('shorebird audit-log --org-id 42 --json')}';

  // Export writes its entries to stdout, so everything else goes to stderr.
  @override
  bool get reservesStdout => true;

  @override
  Future<int> run() async {
    final rest = results.rest;
    final export = switch (rest) {
      [] || ['list'] => false,
      ['export'] => true,
      _ => null,
    };
    if (export == null) {
      return reportError(
        message:
            'Unexpected argument "${rest.join(' ')}". Run '
            '`shorebird audit-log` for one page or '
            '`shorebird audit-log export` for every page.',
      );
    }

    final filters = _parseFilters(export: export);
    if (filters.error != null) return reportError(message: filters.error!);

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organizationId = membership!.organization.id;

    if (!export) return _showPage(organizationId, filters);

    // With --json the runner already keeps stdout for the envelope.
    final out = read(jsonSinkRef, orElse: () => io.stdout);
    if (isJsonMode) return _export(organizationId, filters, out: out);
    // Bound before the redirect, so entries reach the real stdout.
    return runWithStdoutOnStderr(
      () => _export(organizationId, filters, out: out),
    );
  }

  Future<int> _showPage(int organizationId, _Filters filters) async {
    late final GetOrganizationAuditLogsResponse page;
    final fetchError = await _guardFetch(
      () async => page = await _fetch(
        organizationId,
        filters,
        perPage: filters.limit,
        cursor: filters.cursor,
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

    if (page.data.isEmpty) {
      logger.info('No audit log entries.');
    }
    for (final entry in page.data) {
      logger.info(_describe(entry));
    }
    // Oldest first always carries a cursor, so only an empty page there
    // means there is nothing more yet.
    if (page.nextCursor case final cursor? when page.data.isNotEmpty) {
      logger.info('Next page: pass --cursor $cursor with the same filters.');
    }
    return ExitCode.success.code;
  }

  Future<int> _export(
    int organizationId,
    _Filters filters, {
    required io.IOSink out,
  }) async {
    final entries = <Map<String, dynamic>>[];
    var cursor = filters.cursor;
    String? lastCursor;
    final fetchError = await _guardFetch(
      () async {
        do {
          final page = await _fetch(
            organizationId,
            filters,
            perPage: 100,
            cursor: cursor,
          );
          for (final entry in page.data) {
            final json = entry.toJson();
            if (!isJsonMode && filters.format == 'jsonl') {
              out.writeln(jsonEncode(json));
            } else {
              entries.add(json);
            }
          }
          lastCursor = page.nextCursor;
          // Oldest first, every page carries a cursor; an empty page is the
          // end of what there is so far.
          cursor = page.data.isEmpty ? null : page.nextCursor;
        } while (cursor != null);
      },
      organizationId: organizationId,
    );
    if (fetchError != null) return fetchError;

    final resumeCursor = filters.order == AuditLogOrder.asc ? lastCursor : null;
    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organizationId,
        'entries': entries,
        'next_cursor': resumeCursor,
      });
      return ExitCode.success.code;
    }
    if (filters.format == 'json') out.writeln(jsonEncode(entries));
    if (resumeCursor != null) {
      logger.info(
        'To export newer entries later, pass --order asc --cursor '
        '$resumeCursor.',
      );
    }
    return ExitCode.success.code;
  }

  Future<GetOrganizationAuditLogsResponse> _fetch(
    int organizationId,
    _Filters filters, {
    required int? perPage,
    required String? cursor,
  }) {
    return codePushClientWrapper.getOrganizationAuditLogs(
      organizationId: organizationId,
      perPage: perPage,
      cursor: cursor,
      order: filters.order,
      startDate: filters.start,
      endDate: filters.end,
      appId: filters.appId,
      actorId: filters.actorId,
      operation: filters.event,
    );
  }

  /// [guardApiCall] for an audit log fetch, which also says what plan the
  /// audit log needs when the server refuses for that reason.
  Future<int?> _guardFetch(
    Future<void> Function() body, {
    required int organizationId,
  }) async {
    try {
      return await guardApiCall(
        body,
        code: JsonErrorCode.fetchFailed,
        message:
            'Failed to fetch the audit log of organization $organizationId.',
      );
    } on ApiErrorExit catch (exit) {
      if (auditLogErrorHint(exit.error.code) case final hint?) {
        logger.info(hint);
      }
      rethrow;
    }
  }

  _Filters _parseFilters({required bool export}) {
    String? error;
    final actorArg = results['actor'] as String?;
    final actorId = actorArg == null ? null : int.tryParse(actorArg);
    if (actorArg != null && actorId == null) {
      error =
          '"$actorArg" is not an actor id. Pass the id each entry shows '
          'beside its actor, e.g. --actor 12.';
    }

    final limitArg = results['limit'] as String?;
    final limit = limitArg == null ? null : int.tryParse(limitArg);
    if (limitArg != null && (limit == null || limit < 1 || limit > 100)) {
      error = '--limit must be a number from 1 to 100 (got "$limitArg").';
    } else if (limitArg != null && export) {
      error = 'export writes every page; drop --limit.';
    }

    final start = _parseTime('start', endOfDay: false);
    final end = _parseTime('end', endOfDay: true);
    error ??= start.error ?? end.error;

    return _Filters(
      error: error,
      appId: results['app-id'] as String?,
      actorId: actorId,
      event: results['event'] as String?,
      start: start.value,
      end: end.value,
      order: AuditLogOrder.fromJson(results['order'] as String),
      limit: limit,
      cursor: results['cursor'] as String?,
      format: results['format'] as String,
    );
  }

  ({DateTime? value, String? error}) _parseTime(
    String option, {
    required bool endOfDay,
  }) {
    final arg = results[option] as String?;
    if (arg == null) return (value: null, error: null);
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(arg)) {
      final day = DateTime.parse('${arg}T00:00:00Z');
      final value = endOfDay
          ? day.add(const Duration(days: 1, milliseconds: -1))
          : day;
      return (value: value, error: null);
    }
    final value = DateTime.tryParse(arg);
    if (value != null) return (value: value, error: null);
    return (
      value: null,
      error:
          'Pass --$option as a date (2026-10-01) or an ISO 8601 time '
          '(2026-10-01T09:00:00Z), not "$arg".',
    );
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

class _Filters {
  const _Filters({
    required this.error,
    required this.appId,
    required this.actorId,
    required this.event,
    required this.start,
    required this.end,
    required this.order,
    required this.limit,
    required this.cursor,
    required this.format,
  });

  final String? error;
  final String? appId;
  final int? actorId;
  final String? event;
  final DateTime? start;
  final DateTime? end;
  final AuditLogOrder order;
  final int? limit;
  final String? cursor;
  final String format;
}
