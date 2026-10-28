import 'dart:convert';
import 'dart:io' as io;

import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/audit_log/audit_log_filters.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template audit_log_export_command}
/// `shorebird audit-log export`
/// Write every page of an organization's audit log to stdout.
/// {@endtemplate}
class AuditLogExportCommand extends ShorebirdCommand
    with
        OrganizationScopedCommand,
        EnterpriseScopedCommand,
        AuditLogFilterOptions {
  /// {@macro audit_log_export_command}
  AuditLogExportCommand() {
    addFilterOptions();
    argParser
      ..addOption(
        'cursor',
        help: 'Start at this page: the cursor an earlier export printed.',
      )
      ..addOption(
        'format',
        allowed: const ['json', 'jsonl'],
        defaultsTo: 'json',
        allowedHelp: const {
          'json': 'One JSON array.',
          'jsonl': 'One entry per line, written as each page arrives.',
        },
      );
  }

  @override
  String get name => 'export';

  @override
  String get invocation => 'shorebird audit-log export [<org-id>]';

  @override
  String get description =>
      "Writes every page of an organization's audit log to stdout, as OCSF "
      'API Activity events for a security log tool. With --enterprise-id, '
      "writes the enterprise's log instead.\n\n"
      'Examples:\n'
      '  shorebird audit-log export --start 2026-10-01 > audit.json\n'
      '  shorebird audit-log export --order asc --format jsonl '
      '>> audit.jsonl\n\n'
      'Oldest first, it prints the cursor to export newer entries from '
      'later.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird audit-log export 42 --json',
      )}';

  // Entries go to stdout, so everything else goes to stderr.
  @override
  bool get reservesStdout => true;

  String get _format => results['format'] as String;

  @override
  Future<int> run() async {
    if (isJsonMode && results.wasParsed('format')) {
      return reportError(
        message:
            '--json puts the entries in its envelope; drop --format, or drop '
            '--json to write $_format.',
      );
    }
    final (:filters, :error) = parseFilters();
    if (error != null) return reportError(message: error);

    final (scope: resolved, :errorCode) = await resolveScope(
      example: 'shorebird audit-log export <org-id>',
    );
    if (errorCode != null) return errorCode;
    final scope = resolved!;

    // With --json the runner already keeps stdout for the envelope.
    final out = read(jsonSinkRef, orElse: () => io.stdout);
    if (isJsonMode) return _export(scope, filters!, out: out);
    // Bound before the redirect, so entries reach the real stdout.
    return runWithStdoutOnStderr(
      () => _export(scope, filters!, out: out),
    );
  }

  Future<int> _export(
    AuditLogScope scope,
    AuditLogFilters filters, {
    required io.IOSink out,
  }) async {
    final streaming = !isJsonMode && _format == 'jsonl';
    final entries = <Map<String, dynamic>>[];
    var cursor = results['cursor'] as String?;
    var written = 0;
    String? lastCursor;
    final fetchError = await guardFetch(
      () async {
        do {
          final page = await fetchPage(
            scope,
            filters,
            perPage: 100,
            cursor: cursor,
          );
          for (final entry in page.data) {
            if (streaming) {
              out.writeln(jsonEncode(entry.toJson()));
              written++;
            } else {
              entries.add(entry.toJson());
            }
          }
          lastCursor = page.nextCursor;
          // Oldest first, every page carries a cursor; an empty page is the
          // end of what there is so far.
          cursor = page.data.isEmpty ? null : page.nextCursor;
        } while (cursor != null);
      },
      scope: scope,
      // Only a streamed export has written anything to resume after.
      resumeHint: () => streaming && written > 0 && cursor != null
          ? 'The $written entries before the failure were written. To '
                'continue after them: '
                '${_command(scope, cursor!)}'
          : null,
    );
    if (fetchError != null) return fetchError;

    final resumeCursor = filters.order == AuditLogOrder.asc ? lastCursor : null;
    if (isJsonMode) {
      emitJsonSuccess({
        scope.jsonKey: scope.id,
        'entries': entries,
        'next_cursor': resumeCursor,
      });
      return ExitCode.success.code;
    }
    if (_format == 'json') out.writeln(jsonEncode(entries));
    if (resumeCursor != null) {
      logger.info(
        'To export newer entries later: '
        '${_command(scope, resumeCursor)}',
      );
    }
    return ExitCode.success.code;
  }

  String _command(AuditLogScope scope, String cursor) => commandFrom(
    'export',
    scope: scope,
    cursor: cursor,
    extra: [if (results.wasParsed('format')) '--format $_format'],
  );
}
