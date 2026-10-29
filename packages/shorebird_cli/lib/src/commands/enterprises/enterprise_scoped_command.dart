import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The shared `--enterprise` flag, which widens a command to every
/// organization in the user's enterprise, and the logic that finds it.
///
/// An account is in at most one enterprise, so the flag takes no id, but
/// widening the scope still has to be asked for. Call
/// [addEnterpriseScopeFlag] from the command's constructor, then check
/// [enterpriseScope] in `run` and call [resolveEnterprise] when it is set.
mixin EnterpriseScopedCommand on ShorebirdCommand {
  /// Adds the `--enterprise` flag that [enterpriseScope] reads.
  void addEnterpriseScopeFlag({required String help}) {
    argParser.addFlag(
      CommonArguments.enterpriseArg.name,
      negatable: false,
      help: help,
    );
  }

  /// Whether `--enterprise` was passed, widening the command from one
  /// organization to the user's enterprise.
  bool get enterpriseScope =>
      results[CommonArguments.enterpriseArg.name] == true;

  /// Reports `--org-id` and `--enterprise` passed together, which name two
  /// scopes, and returns the exit code; null when at most one is set.
  int? rejectOrganizationAndEnterprise() {
    if (!enterpriseScope || results[CommonArguments.orgIdArg.name] == null) {
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
              '--${CommonArguments.enterpriseArg.name} widens a command to '
              'every organization in your enterprise. Without it, commands '
              'act on one organization (--${CommonArguments.orgIdArg.name}).',
          code: JsonErrorCode.preconditionFailed,
          exitCode: ExitCode.noPerm.code,
        ),
      );
    }
    return (membership: membership, errorCode: null);
  }
}
