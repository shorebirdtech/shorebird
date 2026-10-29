import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Enterprise scope, which widens a command to every organization in the
/// user's enterprise, and the logic that finds the enterprise.
///
/// A command reaches it two ways. The documented one is its copy under
/// `shorebird enterprise` (`shorebird enterprise members list`), built with
/// `enterpriseRoute: true`, which is always enterprise-scoped. The other is
/// a hidden `--enterprise` flag on the command itself (`shorebird members
/// list --enterprise`), kept because agents guess it too.
///
/// An account is in at most one enterprise, so neither takes an id. Call
/// [addEnterpriseScopeFlag] from the command's constructor, then check
/// [enterpriseScope] in `run` and call [resolveEnterprise] when it is set.
mixin EnterpriseScopedCommand on ShorebirdCommand {
  bool _enterpriseRoute = false;

  /// Whether this is the command's copy under `shorebird enterprise`, which
  /// always acts on the enterprise and has no `--enterprise` or `--org-id`.
  bool get isEnterpriseRoute => _enterpriseRoute;

  /// Makes the command enterprise-scoped: always, for its copy under
  /// `shorebird enterprise` ([enterpriseRoute]), or else with the hidden
  /// `--enterprise` flag that [enterpriseScope] reads.
  void addEnterpriseScopeFlag({bool enterpriseRoute = false}) {
    if (enterpriseRoute) {
      _enterpriseRoute = true;
      return;
    }
    argParser.addFlag(
      CommonArguments.enterpriseArg.name,
      negatable: false,
      hide: true,
    );
  }

  /// Whether the command acts on the user's enterprise rather than one
  /// organization: its `shorebird enterprise` copy, or `--enterprise`.
  bool get enterpriseScope =>
      _enterpriseRoute || results[CommonArguments.enterpriseArg.name] == true;

  /// Reports `--org-id` and `--enterprise` passed together, which name two
  /// scopes, and returns the exit code; null when at most one is set.
  int? rejectOrganizationAndEnterprise() {
    if (_enterpriseRoute ||
        !enterpriseScope ||
        results[CommonArguments.orgIdArg.name] == null) {
      return null;
    }
    return reportError(
      message:
          'Pass --${CommonArguments.orgIdArg.name} or '
          '--${CommonArguments.enterpriseArg.name}, not both: '
          '--${CommonArguments.enterpriseArg.name} already covers every '
          'organization in the enterprise.',
    );
  }

  /// Reports a positional organization id passed with `--enterprise`, as in
  /// `shorebird usage 42 --enterprise`, and returns the exit code; null
  /// when there is none.
  int? rejectOrganizationArgumentWithEnterprise() {
    if (!enterpriseScope || results.rest.isEmpty) return null;
    if (_enterpriseRoute) {
      return reportError(
        message:
            'Commands under `shorebird enterprise` cover every '
            'organization in your enterprise, so they take no organization '
            'id. For one organization, run the command without '
            '`enterprise`.',
      );
    }
    return reportError(
      message:
          'Pass an organization id or '
          '--${CommonArguments.enterpriseArg.name}, not both: '
          '--${CommonArguments.enterpriseArg.name} already covers every '
          'organization in the enterprise.',
    );
  }

  /// Finds the user's membership in their enterprise, validating that the
  /// user is signed in. A user who isn't in an enterprise fails.
  ///
  /// Returns `(membership: <membership>, errorCode: null)` on success, or
  /// `(membership: null, errorCode: <code>)` once the failure is reported.
  Future<({EnterpriseMembership? membership, int? errorCode})>
  resolveEnterprise() async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return (membership: null, errorCode: reportPreconditionFailure(error));
    }

    late final List<EnterpriseMembership> enterprises;
    final fetchError = await guardApiCall(
      () async => enterprises = await codePushClientWrapper.getEnterprises(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch your enterprise.',
    );
    if (fetchError != null) return (membership: null, errorCode: fetchError);

    // The server holds each account to one enterprise, so the list has at
    // most one entry. More than one means that rule changed: fail rather
    // than act on one of them, since some of these commands change data.
    if (enterprises.length > 1) {
      final names = enterprises.map((e) => '${e.name} (id: ${e.id})');
      return (
        membership: null,
        errorCode: reportError(
          message:
              'The server says you are in ${enterprises.length} enterprises '
              '(${names.join(', ')}), but an account can be in only one.',
          hint: 'Update shorebird, then report this if it persists.',
          code: JsonErrorCode.softwareError,
          exitCode: ExitCode.software.code,
        ),
      );
    }
    final membership = enterprises.firstOrNull;
    if (membership == null) {
      return (
        membership: null,
        errorCode: reportError(
          message: "You aren't a member of an enterprise.",
          hint:
              '`shorebird enterprise` commands act on every organization in '
              'an enterprise. The same commands without `enterprise` act on '
              'one organization (--${CommonArguments.orgIdArg.name}).',
          code: JsonErrorCode.preconditionFailed,
          exitCode: ExitCode.noPerm.code,
        ),
      );
    }
    return (membership: membership, errorCode: null);
  }
}
