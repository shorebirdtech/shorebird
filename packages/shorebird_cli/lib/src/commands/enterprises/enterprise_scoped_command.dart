import 'package:args/command_runner.dart';
import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
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
/// [addEnterpriseScope] from the command's constructor, then
/// [rejectConflictingScope] first in `run`, then check [enterpriseScope]
/// and call [resolveEnterprise] when it is set.
mixin EnterpriseScopedCommand on ShorebirdCommand {
  bool _enterpriseRoute = false;

  /// Whether this is the command's copy under `shorebird enterprise`, which
  /// always acts on the enterprise.
  bool get isEnterpriseRoute => _enterpriseRoute;

  /// Makes the command enterprise-scoped: always, for its copy under
  /// `shorebird enterprise` ([route]), or else with the hidden
  /// `--enterprise` flag that [enterpriseScope] reads.
  ///
  /// The copy takes a hidden `--enterprise` too, which changes nothing, so
  /// `shorebird enterprise members list --enterprise` works, and a hidden
  /// `--org-id`, which [rejectConflictingScope] answers by naming the
  /// command for one organization.
  void addEnterpriseScope({required bool route}) {
    _enterpriseRoute = route;
    argParser.addFlag(
      CommonArguments.enterpriseArg.name,
      negatable: false,
      hide: true,
    );
    if (route) argParser.addOption(CommonArguments.orgIdArg.name, hide: true);
  }

  /// Whether the command acts on the user's enterprise rather than one
  /// organization: its `shorebird enterprise` copy, or `--enterprise`.
  bool get enterpriseScope =>
      _enterpriseRoute || results[CommonArguments.enterpriseArg.name] == true;

  /// The command's words after `shorebird`, leaving out `enterprise`, such
  /// as `members list`.
  String get _commandPath {
    final names = <String>[];
    for (Command<int>? command = this; command != null;) {
      final parent = command.parent;
      if (!(parent == null && command.name == 'enterprise')) {
        names.insert(0, command.name);
      }
      command = parent;
    }
    return names.join(' ');
  }

  /// This command as run on the whole enterprise, such as
  /// `shorebird enterprise members list`.
  String get enterpriseCommandLine => 'shorebird enterprise $_commandPath';

  /// This command as run on one organization, such as
  /// `shorebird members list`.
  String get organizationCommandLine => 'shorebird $_commandPath';

  /// The command line the user is running: [enterpriseCommandLine] under
  /// enterprise scope, else [organizationCommandLine]. Hints that repeat
  /// the command use it.
  String get commandLine =>
      enterpriseScope ? enterpriseCommandLine : organizationCommandLine;

  /// Reports an organization named alongside enterprise scope and returns
  /// the exit code; null when there is no conflict.
  ///
  /// An organization is named by `--org-id` or, unless the command's
  /// positional arguments mean something else ([takesUserArgument], as for
  /// `members remove bob@acme.com`), by a positional id
  /// (`shorebird usage 42`).
  int? rejectConflictingScope({bool takesUserArgument = false}) {
    if (!enterpriseScope) return null;
    final hasOrgIdOption = argParser.options.containsKey(
      CommonArguments.orgIdArg.name,
    );
    final orgId = hasOrgIdOption
        ? results[CommonArguments.orgIdArg.name] as String?
        : null;
    final positional = !takesUserArgument && results.rest.isNotEmpty;
    if (orgId == null && !positional) return null;
    final named = orgId != null
        ? '--${CommonArguments.orgIdArg.name}'
        : 'organization id';
    // `orgs list` and `apps list` have no one-organization form: without
    // `enterprise` they list what you can access.
    final organizationCommand = this is OrganizationScopedCommand
        ? '`$organizationCommandLine --${CommonArguments.orgIdArg.name} '
              '<id>` for one organization'
        : '`$organizationCommandLine` for the ones you can access';
    return reportError(
      message: _enterpriseRoute
          ? '`$enterpriseCommandLine` covers every organization in your '
                'enterprise, so it takes no $named.'
          : '--${CommonArguments.enterpriseArg.name} covers every '
                'organization in your enterprise, so it takes no $named.',
      hint: _enterpriseRoute
          ? 'Drop `enterprise`: run $organizationCommand.'
          : 'Run $organizationCommand, or `$enterpriseCommandLine` for '
                'every organization in your enterprise.',
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
