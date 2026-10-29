import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/members/member_target.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template members_list_command}
/// `shorebird members list`
/// List an organization's members and pending invitations.
/// {@endtemplate}
class MembersListCommand extends ShorebirdCommand
    with OrganizationScopedCommand, EnterpriseScopedCommand {
  /// {@macro members_list_command}
  ///
  /// With [enterpriseRoute], it is `shorebird enterprise members list`.
  MembersListCommand({bool enterpriseRoute = false})
    : this._(enterpriseRoute: enterpriseRoute, guestsRoute: false);

  /// `shorebird enterprise guests list`: the enterprise's guests, always.
  MembersListCommand.enterpriseGuests()
    : this._(enterpriseRoute: true, guestsRoute: true);

  MembersListCommand._({
    required bool enterpriseRoute,
    required bool guestsRoute,
  }) : _guestsRoute = guestsRoute {
    if (!enterpriseRoute) addOrganizationScopeOption();
    addEnterpriseScope(route: enterpriseRoute);
    if (!guestsRoute) {
      argParser.addFlag(
        _guestsFlag,
        negatable: false,
        hide: !enterpriseRoute,
        help:
            "List the enterprise's guests instead: people in its "
            "organizations who aren't in its directory (the same as "
            '`shorebird enterprise guests`).',
      );
    }
  }

  static const _guestsFlag = 'guests';

  final bool _guestsRoute;

  @override
  String get name => 'list';

  @override
  String get description {
    if (_guestsRoute) {
      return "Lists your enterprise's guests: people in its organizations "
          "who aren't in its directory. Needs an owner or admin of the "
          'enterprise.\n\n'
          'Example output (space-separated: id  email  role  '
          'organizations):\n'
          '  31  carol@vendor.com  guest  1 organization\n\n'
          '${ShorebirdCommand.jsonHint('shorebird enterprise guests --json')}';
    }
    if (isEnterpriseRoute) {
      return "Lists your enterprise's directory: everyone in it, with their "
          'enterprise role. Needs an owner or admin of the enterprise.\n\n'
          'Example output (space-separated: id  email  enterprise_role  '
          'organizations):\n'
          '  12  alice@acme.com  admin  3 organizations\n\n'
          'Add --guests (or run `shorebird enterprise guests`) for the people '
          'in its organizations who are not in its directory.\n\n'
          '${ShorebirdCommand.jsonHint(
            'shorebird enterprise members list --json',
          )}';
    }
    return _organizationDescription;
  }

  String get _organizationDescription =>
      "Lists an organization's members and pending invitations.\n\n"
      'Example output (space-separated: id  email  role  status):\n'
      '  12  alice@acme.com  owner  member\n'
      '  0b6c...  bob@acme.com  developer  invited (expires 2026-11-10)\n\n'
      'The id is the user id of a member and the invitation id of a pending '
      'invitation; `members set-role` and `members remove` take either, or '
      'the email.\n\n'
      'Invite someone with `shorebird members add <email>`.\n\n'
      "For your enterprise's directory, run "
      '`shorebird enterprise members list`.\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird members list --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final scopeError = rejectConflictingScope();
    if (scopeError != null) return scopeError;
    final guests = _guestsRoute || results[_guestsFlag] == true;
    if (enterpriseScope) {
      return guests ? _listEnterpriseGuests() : _listEnterpriseMembers();
    }
    if (guests) {
      return reportError(
        message:
            "--$_guestsFlag lists an enterprise's guests; run "
            '`shorebird enterprise guests`.',
      );
    }

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return errorCode;
    final organization = membership!.organization;

    late final List<OrganizationUser> members;
    late final List<InvitationSummary>? invitations;
    final fetchError = await guardApiCall(
      () async {
        members = await codePushClientWrapper.getOrganizationUsers(
          organizationId: organization.id,
        );
        invitations = await codePushClientWrapper
            .maybeGetOrganizationInvitations(organizationId: organization.id);
      },
      code: JsonErrorCode.fetchFailed,
      message:
          'Failed to fetch the members of organization ${organization.id}.',
    );
    if (fetchError != null) return fetchError;

    // The auditor role can't see invitations; list the members anyway.
    const invitationsHiddenMessage =
        'Pending invitations are not shown: your role in this organization '
        "can't see them.";

    if (isJsonMode) {
      emitJsonSuccess({
        'organization_id': organization.id,
        'invitations_shown': invitations != null,
        'members': [
          for (final member in members)
            {
              'status': 'member',
              'user_id': member.user.id,
              'email': member.user.email,
              'name': member.user.displayName,
              'role': member.role.value,
            },
          for (final invite in invitations ?? <InvitationSummary>[])
            {
              'status': 'invited',
              'invitation_id': invite.id,
              'email': invite.email,
              'role': invite.role.value,
              'invited_at': invite.createdAt.toUtc().toIso8601String(),
              'expires_at': invite.expiresAt.toUtc().toIso8601String(),
            },
        ],
      });
      return ExitCode.success.code;
    }

    for (final member in members) {
      logger.info(
        '${member.user.id}  ${lightCyan.wrap(member.user.email)}  '
        '${member.role.value}  member',
      );
    }
    final shownInvitations = invitations;
    if (shownInvitations == null) {
      logger.warn(invitationsHiddenMessage);
      return ExitCode.success.code;
    }
    for (final invite in shownInvitations) {
      logger.info(
        '${invite.id}  ${lightCyan.wrap(invite.email)}  ${invite.role.value}  '
        'invited (expires ${_date(invite.expiresAt)})',
      );
    }
    return ExitCode.success.code;
  }

  Future<int> _listEnterpriseMembers() async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    late final List<EnterpriseMember> members;
    final fetchError = await guardApiCall(
      () async => members = await codePushClientWrapper.getEnterpriseMembers(
        enterpriseId: enterprise.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the members of "${enterprise.name}".',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'members': [
          for (final m in members)
            {
              'user_id': m.userId,
              'email': m.email,
              'name': m.displayName,
              'role': m.role.value,
              'organizations': _organizationsJson(m.teams),
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (members.isEmpty) {
      logger.info('"${enterprise.name}" has no members.');
      return ExitCode.success.code;
    }
    for (final m in members) {
      final label = _label(m.userId, m.email, m.displayName);
      logger.info(
        '${m.userId}  ${lightCyan.wrap(label)}  '
        '${m.role.value}  ${_organizationCount(m.teams)}',
      );
    }
    return ExitCode.success.code;
  }

  Future<int> _listEnterpriseGuests() async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    late final List<EnterpriseGuest> guests;
    final fetchError = await guardApiCall(
      () async => guests = await codePushClientWrapper.getEnterpriseGuests(
        enterpriseId: enterprise.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch the guests of "${enterprise.name}".',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        'guests': [
          for (final g in guests)
            {
              'user_id': g.userId,
              'email': g.email,
              'name': g.displayName,
              'organizations': _organizationsJson(g.teams),
              'outside_guest_policy': g.outsideGuestPolicy,
            },
        ],
      });
      return ExitCode.success.code;
    }

    if (guests.isEmpty) {
      logger.info('"${enterprise.name}" has no guests.');
      return ExitCode.success.code;
    }
    for (final g in guests) {
      final label = _label(g.userId, g.email, g.displayName);
      logger.info(
        '${g.userId}  ${lightCyan.wrap(label)}  '
        'guest  ${_organizationCount(g.teams)}'
        '${g.outsideGuestPolicy ? '  outside guest policy' : ''}',
      );
    }
    return ExitCode.success.code;
  }
}

String _label(int userId, String? email, String? displayName) =>
    enterpriseUserLabel(userId: userId, email: email, displayName: displayName);

List<Map<String, Object>> _organizationsJson(
  List<EnterpriseTeamAccess> teams,
) => [
  for (final t in teams) {'organization_id': t.teamId, 'role': t.role.value},
];

String _organizationCount(List<EnterpriseTeamAccess> teams) =>
    formatCount(teams.length, 'organization');

/// [time]'s UTC calendar date, as YYYY-MM-DD.
String _date(DateTime time) => time.toUtc().toIso8601String().substring(0, 10);
