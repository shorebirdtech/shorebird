import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/organization_id.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Help text for `--org-id` on commands that act on one organization.
const organizationScopedOrgIdHelp =
    'The id of the organization (e.g. "42"). Defaults to the organization '
    "of the app in this directory's shorebird.yaml, or to your only "
    'organization.';

/// The shared `--org-id` option for commands that act on one organization,
/// and the logic that picks the organization.
///
/// Call [addOrganizationScopeOption] from the command's constructor, then
/// [resolveOrganization] from `run`.
mixin OrganizationScopedCommand on ShorebirdCommand {
  /// Adds the `--org-id` option that [resolveOrganization] reads.
  void addOrganizationScopeOption() {
    argParser.addOption(
      CommonArguments.orgIdArg.name,
      aliases: const ['organization-id'],
      help: organizationScopedOrgIdHelp,
    );
  }

  /// Picks the organization to act on, validating that the user is signed
  /// in, and returns the user's membership in it.
  ///
  /// The organization is, in order: the one [orgId] names (by default the
  /// `--org-id` value); the one that owns the app in the current directory's
  /// shorebird.yaml; the user's only organization. Otherwise this fails,
  /// listing the user's organizations. A default is announced, so the user
  /// sees which organization the command acts on.
  ///
  /// Returns `(membership: <membership>, errorCode: null)` on success, or
  /// `(membership: null, errorCode: <code>)` once the failure is reported.
  Future<({OrganizationMembership? membership, int? errorCode})>
  resolveOrganization({String? orgId}) async {
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (error) {
      return (membership: null, errorCode: reportPreconditionFailure(error));
    }

    late final List<OrganizationMembership> memberships;
    final fetchError = await guardApiCall(
      () async => memberships = await codePushClientWrapper
          .getOrganizationMemberships(),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch organizations.',
    );
    if (fetchError != null) return (membership: null, errorCode: fetchError);

    final orgIdArg = orgId ?? results[CommonArguments.orgIdArg.name] as String?;
    if (orgIdArg != null) {
      final (:id, error: parseError) = parseOrganizationId(
        orgIdArg,
        memberships: memberships,
      );
      final (:membership, :error) = parseError != null
          ? (membership: null, error: parseError)
          : findOrganizationMembership(id: id!, memberships: memberships);
      if (error != null) {
        return (
          membership: null,
          errorCode: reportError(message: error.message, hint: error.hint),
        );
      }
      return (membership: membership, errorCode: null);
    }

    final appId = shorebirdEnv.getShorebirdYaml()?.appId;
    if (appId != null) {
      OrganizationMembership? appMembership;
      final appError = await guardApiCall(
        () async {
          final app = await codePushClientWrapper.maybeGetApp(appId: appId);
          if (app == null) return;
          appMembership = await codePushClientWrapper.findAppOrganization(
            appId: appId,
            memberships: memberships,
            organizationId: app.organizationId,
          );
        },
        code: JsonErrorCode.fetchFailed,
        message: 'Failed to find the organization of app "$appId".',
      );
      if (appError != null) return (membership: null, errorCode: appError);
      // Falling back to another organization here could act on one the
      // user doesn't mean, so make them pick.
      if (appMembership == null) {
        return (
          membership: null,
          errorCode: reportError(
            message:
                'App "$appId" in shorebird.yaml is not in any of your '
                'organizations. Pass --${CommonArguments.orgIdArg.name} to '
                'choose one.',
            hint: availableOrganizations(memberships),
          ),
        );
      }
      _announceDefault(appMembership!, 'which owns the app in shorebird.yaml');
      return (membership: appMembership, errorCode: null);
    }

    if (memberships.length == 1) {
      _announceDefault(memberships.single, 'your only organization');
      return (membership: memberships.single, errorCode: null);
    }

    return (
      membership: null,
      errorCode: reportError(
        message:
            'Pass --${CommonArguments.orgIdArg.name} to choose an '
            'organization.',
        hint: availableOrganizations(memberships),
      ),
    );
  }

  /// [resolveOrganization] for a command whose only argument is the
  /// organization id, as in `shorebird orgs get 42`, so that a positional id
  /// is never dropped in favor of a default. [example] is the command with
  /// `<org-id>` where the id goes, for the error when it is given twice.
  Future<({OrganizationMembership? membership, int? errorCode})>
  resolveOrganizationFromArguments({required String example}) async {
    final option = results[CommonArguments.orgIdArg.name] as String?;
    final rest = results.rest;
    if (rest.length > 1 || (rest.isNotEmpty && option != null)) {
      return (
        membership: null,
        errorCode: reportError(
          message:
              'Pass one organization id, not '
              '${[?option, ...rest].map((id) => '"$id"').join(' and ')}: '
              '$example.',
        ),
      );
    }
    return resolveOrganization(orgId: option ?? rest.firstOrNull);
  }

  void _announceDefault(OrganizationMembership membership, String reason) {
    if (isJsonMode) return;
    final org = membership.organization;
    logger.info(
      'Using organization "${org.name}" (id: ${org.id}), $reason. Pass '
      '--${CommonArguments.orgIdArg.name} to choose another.',
    );
  }
}
