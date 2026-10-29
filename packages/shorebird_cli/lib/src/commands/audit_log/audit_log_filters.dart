import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/src/base/process.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// What to do next after the audit log API refused a request with
/// [apiCode], or null when the server's own message says enough.
///
/// Doesn't name a plan: which plans include the audit log is the server's
/// call, and can change without a CLI release.
String? auditLogErrorHint(String? apiCode) => switch (apiCode) {
  'shorebird_plan_insufficient_tier' =>
    "Your plan doesn't include the audit log. See "
        'https://shorebird.dev/pricing.',
  _ => null,
};

/// Whose audit log a run reads: one organization's, or an enterprise's,
/// which covers every organization in it.
class AuditLogScope {
  /// Organization [id]'s log.
  const AuditLogScope.organization(this.id) : isEnterprise = false, name = null;

  /// The log of enterprise [id], called [name].
  const AuditLogScope.enterprise(this.id, {required String this.name})
    : isEnterprise = true;

  /// The organization or enterprise id.
  final int id;

  /// Whether [id] names an enterprise.
  final bool isEnterprise;

  /// The enterprise's name; null for an organization.
  final String? name;

  /// The command that reads this scope's log, before its subcommand. The
  /// user is in at most one enterprise, so its command names no id.
  String get command =>
      isEnterprise ? 'shorebird enterprise audit-log' : 'shorebird audit-log';

  /// The options that name this scope after the subcommand: none for the
  /// enterprise, whose [command] already says it.
  List<String> get options =>
      isEnterprise ? const [] : ['--${CommonArguments.orgIdArg.name} $id'];

  /// This scope in a sentence, such as "organization 42" or `"Acme"`.
  String get label => isEnterprise ? '"$name"' : 'organization $id';

  /// The `--json` key that holds [id].
  String get jsonKey => isEnterprise ? 'enterprise_id' : 'organization_id';
}

/// The audit log filters a run was given, parsed.
class AuditLogFilters {
  /// Creates filters; null leaves a filter off.
  const AuditLogFilters({
    required this.order,
    this.appId,
    this.actorId,
    this.event,
    this.start,
    this.end,
  });

  /// The order entries come in.
  final AuditLogOrder order;

  /// Only entries about this app.
  final String? appId;

  /// Only entries this user or service account caused.
  final int? actorId;

  /// Only entries of this event, such as `organization.rename`.
  final String? event;

  /// Only entries at or after this time.
  final DateTime? start;

  /// Only entries at or before this time.
  final DateTime? end;
}

/// The filter options `shorebird audit-log list` and `export` share,
/// and the fetch and error reporting around them.
mixin AuditLogFilterOptions
    on OrganizationScopedCommand, EnterpriseScopedCommand {
  /// The filter options, in the order a resume hint repeats them.
  static const _filterOptions = [
    'app-id',
    'actor',
    'event',
    'start',
    'end',
    'order',
  ];

  /// Adds `--org-id` and the filter options [parseFilters] reads; for the
  /// `shorebird enterprise audit-log` copy ([enterpriseRoute]), the filter
  /// options and the hidden `--org-id` of [addEnterpriseScope].
  void addFilterOptions({bool enterpriseRoute = false}) {
    if (!enterpriseRoute) addOrganizationScopeOption();
    addEnterpriseScope(route: enterpriseRoute);
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
        help: enterpriseRoute
            ? 'Only entries of this event (e.g. "enterprise_member.remove").'
            : 'Only entries of this event (e.g. "organization.rename").',
      )
      ..addOption(
        'start',
        aliases: const ['since'],
        help:
            'Only entries at or after this time: a date (2026-10-01, the '
            'start of that day UTC) or a time with its zone '
            '(2026-10-01T09:00:00Z).',
      )
      ..addOption(
        'end',
        aliases: const ['until'],
        help:
            'Only entries at or before this time: a date (the end of that '
            'day UTC) or a time with its zone.',
      )
      ..addOption(
        'order',
        allowed: const ['desc', 'asc'],
        defaultsTo: 'desc',
        allowedHelp: const {'desc': 'Newest first.', 'asc': 'Oldest first.'},
      );
  }

  /// The filters this run was given, or why they are invalid.
  ({AuditLogFilters? filters, String? error}) parseFilters() {
    final actorArg = results['actor'] as String?;
    final actorId = actorArg == null ? null : int.tryParse(actorArg);
    if (actorArg != null && actorId == null) {
      return (
        filters: null,
        error:
            '"$actorArg" is not an actor id. Pass the id each entry shows '
            'beside its actor, e.g. --actor 12.',
      );
    }

    final start = _parseTime('start', endOfDay: false);
    if (start.error != null) return (filters: null, error: start.error);
    final end = _parseTime('end', endOfDay: true);
    if (end.error != null) return (filters: null, error: end.error);
    if (start.value != null &&
        end.value != null &&
        start.value!.isAfter(end.value!)) {
      return (
        filters: null,
        error:
            '--start (${results['start']}) is after --end '
            '(${results['end']}), so no entry could match.',
      );
    }

    return (
      filters: AuditLogFilters(
        order: AuditLogOrder.fromJson(results['order'] as String),
        appId: results['app-id'] as String?,
        actorId: actorId,
        event: results['event'] as String?,
        start: start.value,
        end: end.value,
      ),
      error: null,
    );
  }

  ({DateTime? value, String? error}) _parseTime(
    String option, {
    required bool endOfDay,
  }) {
    final arg = results[option] as String?;
    if (arg == null) return (value: null, error: null);
    if (_date.hasMatch(arg)) {
      final day = DateTime.tryParse('${arg}T00:00:00Z');
      // DateTime.parse rolls 2026-02-30 over into March; refuse it instead.
      if (day != null && day.toIso8601String().startsWith(arg)) {
        final value = endOfDay
            ? day.add(const Duration(days: 1, milliseconds: -1))
            : day;
        return (value: value, error: null);
      }
    } else if (_timeWithZone.hasMatch(arg)) {
      final value = DateTime.tryParse(arg);
      if (value != null) return (value: value, error: null);
    }
    return (
      value: null,
      error:
          'Pass --$option as a date (2026-10-01) or a time with its zone '
          '(2026-10-01T09:00:00Z), not "$arg".',
    );
  }

  /// Picks whose log to read: your enterprise under `shorebird
  /// enterprise`, else the organization as
  /// [resolveOrganizationFromArguments] picks it.
  /// [example] is the command with `<org-id>` where the id goes.
  ///
  /// Returns the scope, or an exit code once the failure is reported.
  Future<({AuditLogScope? scope, int? errorCode})> resolveScope({
    required String example,
  }) async {
    if (isEnterpriseRoute) {
      final scopeError = rejectConflictingScope();
      if (scopeError != null) return (scope: null, errorCode: scopeError);
      final (:membership, :errorCode) = await resolveEnterprise();
      if (errorCode != null) return (scope: null, errorCode: errorCode);
      return (
        scope: AuditLogScope.enterprise(
          membership!.id,
          name: membership.name,
        ),
        errorCode: null,
      );
    }
    final (:membership, :errorCode) = await resolveOrganizationFromArguments(
      example: example,
    );
    if (errorCode != null) return (scope: null, errorCode: errorCode);
    return (
      scope: AuditLogScope.organization(membership!.organization.id),
      errorCode: null,
    );
  }

  /// The command that runs [subcommand] again with this run's scope and
  /// filters, starting at [cursor], plus [extra] options.
  String commandFrom(
    String subcommand, {
    required AuditLogScope scope,
    required String cursor,
    List<String> extra = const [],
  }) {
    final options = [
      ...scope.options,
      for (final option in _filterOptions)
        if (results.wasParsed(option)) '--$option ${_quote(results[option])}',
      ...extra,
      '--cursor ${_quote(cursor)}',
    ];
    return '${scope.command} $subcommand ${options.join(' ')}';
  }

  /// Fetches one page of [scope]'s audit log matching [filters].
  Future<GetOrganizationAuditLogsResponse> fetchPage(
    AuditLogScope scope,
    AuditLogFilters filters, {
    required int? perPage,
    required String? cursor,
  }) {
    if (scope.isEnterprise) {
      return codePushClientWrapper.getEnterpriseAuditLogs(
        enterpriseId: scope.id,
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
    return codePushClientWrapper.getOrganizationAuditLogs(
      organizationId: scope.id,
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

  /// [guardApiCall] for audit log fetches: also says, in either output
  /// mode, why a plan refusal happened, and [resumeHint] when [body] fails
  /// partway (a function, since [body] decides where it stopped).
  Future<int?> guardFetch(
    Future<void> Function() body, {
    required AuditLogScope scope,
    String? Function()? resumeHint,
  }) async {
    final message = 'Failed to fetch the audit log of ${scope.label}.';
    try {
      await body();
      return null;
    } on PreconditionFailedExit {
      rethrow;
    } on ApiErrorExit catch (exit) {
      final hint = _joinHints([
        auditLogErrorHint(exit.error.code),
        resumeHint?.call(),
      ]);
      if (!isJsonMode) {
        if (hint != null) logger.info(hint);
        rethrow;
      }
      emitJsonError(
        code: JsonErrorCode.fetchFailed,
        message: '$message ${exit.error.message}',
        hint: hint,
        apiCode: exit.error.code,
        details: exit.error.details,
        documentationUrl: exit.error.documentationUrl,
      );
      return ExitCode.software.code;
    } on ProcessExit catch (exit) {
      final hint = resumeHint?.call();
      if (!isJsonMode) {
        if (hint != null) logger.info(hint);
        rethrow;
      }
      emitJsonError(
        code: JsonErrorCode.fetchFailed,
        message: message,
        hint: hint,
      );
      return exit.exitCode;
    }
  }
}

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _timeWithZone = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$',
);

String? _joinHints(List<String?> hints) {
  final present = hints.nonNulls;
  return present.isEmpty ? null : present.join('\n');
}

String _quote(Object? value) {
  final text = '$value';
  return RegExp(r'^[\w.:@+/-]+$').hasMatch(text) ? text : "'$text'";
}
