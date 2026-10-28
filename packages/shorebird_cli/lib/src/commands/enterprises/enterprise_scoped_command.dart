import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// The shared `--enterprise-id` option, which widens a command to every
/// organization in an enterprise, and the logic that finds the enterprise.
///
/// The enterprise is never inferred: widening the scope has to be asked
/// for. Call [addEnterpriseScopeOption] from the command's constructor,
/// then check [enterpriseIdOption] in `run` and call [resolveEnterprise]
/// when it is set.
mixin EnterpriseScopedCommand on ShorebirdCommand {
  /// Adds the `--enterprise-id` option that [resolveEnterprise] reads.
  void addEnterpriseScopeOption({required String help}) {
    argParser.addOption(CommonArguments.enterpriseIdArg.name, help: help);
  }

  /// The `--enterprise-id` value, or null when the command acts on one
  /// organization.
  String? get enterpriseIdOption =>
      results[CommonArguments.enterpriseIdArg.name] as String?;

  /// Reports `--org-id` and `--enterprise-id` passed together, which name
  /// two scopes, and returns the exit code; null when at most one is set.
  int? rejectOrganizationAndEnterprise() {
    if (enterpriseIdOption == null ||
        results[CommonArguments.orgIdArg.name] == null) {
      return null;
    }
    return reportError(
      message:
          'Pass --${CommonArguments.orgIdArg.name} or '
          '--${CommonArguments.enterpriseIdArg.name}, not both: '
          '--${CommonArguments.enterpriseIdArg.name} already covers every '
          'organization in the enterprise.',
    );
  }

  /// Reports a positional organization id passed with `--enterprise-id`,
  /// as in `shorebird usage 42 --enterprise-id 7`, and returns the exit
  /// code; null when there is none.
  int? rejectOrganizationArgumentWithEnterprise() {
    if (enterpriseIdOption == null || results.rest.isEmpty) return null;
    return reportError(
      message:
          'Pass an organization id or '
          '--${CommonArguments.enterpriseIdArg.name}, not both: '
          '--${CommonArguments.enterpriseIdArg.name} already covers every '
          'organization in the enterprise.',
    );
  }

  /// Finds the user's membership in the enterprise [enterpriseId] names (by
  /// default the `--enterprise-id` value), validating that the user is
  /// signed in. An id that isn't one of the user's enterprises fails,
  /// listing them. With no id, [defaultToOnly] picks the user's only
  /// enterprise, for commands that read one and widen nothing.
  ///
  /// Returns `(membership: <membership>, errorCode: null)` on success, or
  /// `(membership: null, errorCode: <code>)` once the failure is reported.
  Future<({EnterpriseMembership? membership, int? errorCode})>
  resolveEnterprise({String? enterpriseId, bool defaultToOnly = false}) async {
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
      message: 'Failed to fetch enterprises.',
    );
    if (fetchError != null) return (membership: null, errorCode: fetchError);

    final arg = enterpriseId ?? enterpriseIdOption;
    if (arg == null && defaultToOnly && enterprises.length == 1) {
      return (membership: enterprises.single, errorCode: null);
    }
    final id = arg == null ? null : int.tryParse(arg);
    if (id == null) {
      return (
        membership: null,
        errorCode: reportError(
          message: arg == null
              ? 'Pass an enterprise id.'
              : '"$arg" is not a valid enterprise id.',
          hint:
              'Enterprise ids are integers, e.g. '
              '--${CommonArguments.enterpriseIdArg.name} 7. '
              '${availableEnterprises(enterprises)}',
        ),
      );
    }
    final membership = enterprises.firstWhereOrNull((e) => e.id == id);
    if (membership == null) {
      return (
        membership: null,
        errorCode: reportError(
          message: 'You are not a member of enterprise $id.',
          hint: availableEnterprises(enterprises),
        ),
      );
    }
    return (membership: membership, errorCode: null);
  }
}

/// Lists [enterprises] with their ids on one line, for a hint that reads the
/// same in human and JSON output.
String availableEnterprises(List<EnterpriseMembership> enterprises) {
  if (enterprises.isEmpty) return 'You are not a member of any enterprise.';
  final named = enterprises.map((e) => '${e.name} (id: ${e.id})');
  return 'Your enterprises: ${named.join(', ')}.';
}
