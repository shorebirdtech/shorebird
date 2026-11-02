import 'package:args/command_runner.dart';
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
/// A command reaches it through its copy under `shorebird enterprise`
/// (`shorebird enterprise members list`), built with `enterpriseRoute:
/// true`, which is always enterprise-scoped. There is no `--enterprise`
/// flag: one way to do each thing.
///
/// An account is in at most one enterprise, so the copy takes no id. Set
/// [isEnterpriseRoute] from the command's constructor, then call
/// [rejectConflictingScope] first in `run`, then check [isEnterpriseRoute]
/// and call [resolveEnterprise] when it is set.
mixin EnterpriseScopedCommand on ShorebirdCommand {
  /// Whether this is the command's copy under `shorebird enterprise`, which
  /// always acts on the enterprise and has no `--org-id`. Set it from the
  /// command's constructor.
  bool isEnterpriseRoute = false;

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
      isEnterpriseRoute ? enterpriseCommandLine : organizationCommandLine;

  /// Reports a positional organization id (`shorebird enterprise usage
  /// 42`) under enterprise scope and returns the exit code; null when there
  /// is none. Commands whose positional arguments mean something else
  /// ([takesUserArgument], as for `members remove bob@acme.com`) skip it.
  int? rejectConflictingScope({bool takesUserArgument = false}) {
    if (!isEnterpriseRoute || takesUserArgument || results.rest.isEmpty) {
      return null;
    }
    return reportError(
      message:
          '`$enterpriseCommandLine` covers every organization in your '
          'enterprise, so it takes no organization id.',
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
