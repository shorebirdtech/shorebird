import 'package:collection/collection.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Help for the `--role` option of service account commands.
final serviceAccountRoleHelp =
    'The role of the service account: '
    '${ServiceAccountRole.values.map((r) => r.value).join(', ')}. Service '
    'accounts are never admins or owners.';

/// The `--role` values service account commands accept.
final serviceAccountRoleValues = [
  for (final role in ServiceAccountRole.values) role.value,
];

/// A service account and the user's membership in the organization that owns
/// it.
typedef ResolvedServiceAccount = ({
  OrganizationMembership membership,
  ServiceAccount account,
});

/// The prefix that names a service account by id alone, as in `id:383`, for
/// when a number is also another account's name.
const serviceAccountIdPrefix = 'id:';

/// Finds a service account, named by its name or id as the first argument,
/// in the organization an [OrganizationScopedCommand] picks.
///
/// Call [addOrganizationScopeOption] from the command's constructor, then
/// [resolveServiceAccount] from `run`.
mixin ServiceAccountScopedCommand
    on ShorebirdCommand, OrganizationScopedCommand {
  /// The command line that runs this command on a service account, for
  /// error messages, e.g. `shorebird service-accounts get`.
  String get commandLine;

  /// How many arguments the command takes, the service account included.
  int get maxArguments => 1;

  /// Picks the organization, then finds the service account the first
  /// argument names: by name or id, or by id alone with `id:<id>`.
  ///
  /// Fails before any request when there are more than [maxArguments]
  /// arguments. Fails, listing the organization's service accounts, when the
  /// argument is missing, matches none, or matches more than one (an id and
  /// another account's name, or a name two accounts share), so a command
  /// never acts on an account the user didn't mean.
  ///
  /// Returns `(resolved: <account>, errorCode: null)` on success, or
  /// `(resolved: null, errorCode: <code>)` once the failure is reported.
  Future<({ResolvedServiceAccount? resolved, int? errorCode})>
  resolveServiceAccount() async {
    final rest = results.rest;
    if (rest.length > maxArguments) {
      return (
        resolved: null,
        errorCode: reportError(
          message:
              'Too many arguments: '
              '${rest.map(shellQuote).join(' ')}.',
          hint: 'Usage: $invocation',
        ),
      );
    }
    final nameOrId = rest.firstOrNull;

    final (:membership, :errorCode) = await resolveOrganization();
    if (errorCode != null) return (resolved: null, errorCode: errorCode);
    final organization = membership!.organization;

    late final List<ServiceAccount> accounts;
    final fetchError = await guardApiCall(
      () async => accounts = await codePushClientWrapper.getServiceAccounts(
        organizationId: organization.id,
      ),
      code: JsonErrorCode.fetchFailed,
      message:
          'Failed to fetch the service accounts of "${organization.name}".',
    );
    if (fetchError != null) return (resolved: null, errorCode: fetchError);

    final hint = accounts.isEmpty
        ? '"${organization.name}" has no service accounts. Create one with '
              'shorebird service-accounts create <name>.'
        : 'Service accounts in "${organization.name}": '
              '${accounts.map(_describe).join(', ')}.';

    if (nameOrId == null) {
      return (
        resolved: null,
        errorCode: reportError(
          message: 'Name the service account: $commandLine <name or id>.',
          hint: hint,
        ),
      );
    }

    final List<ServiceAccount> matches;
    if (nameOrId.startsWith(serviceAccountIdPrefix)) {
      final id = int.tryParse(
        nameOrId.substring(serviceAccountIdPrefix.length),
      );
      matches = accounts.where((a) => a.id == id).toList();
    } else {
      final id = int.tryParse(nameOrId);
      matches = accounts
          .where((a) => a.name == nameOrId || a.id == id)
          .toList();
    }

    if (matches.length > 1) {
      return (
        resolved: null,
        errorCode: reportError(
          message:
              '"$nameOrId" matches ${matches.length} service accounts in '
              '"${organization.name}": ${matches.map(_describe).join(', ')}.',
          hint:
              'Pick one by id, e.g. $commandLine '
              '$serviceAccountIdPrefix${matches.first.id}',
        ),
      );
    }
    if (matches.isEmpty) {
      return (
        resolved: null,
        errorCode: reportError(
          message:
              'No service account "$nameOrId" in "${organization.name}" '
              '(id: ${organization.id}).',
          hint: hint,
        ),
      );
    }
    return (
      resolved: (membership: membership, account: matches.single),
      errorCode: null,
    );
  }

  /// [account]'s name (quoted for a shell when needed) and id.
  String _describe(ServiceAccount account) =>
      '${shellQuote(account.name)} (id: ${account.id})';
}

/// [value], single-quoted when a shell would split or expand it, so a
/// command built from it runs when pasted.
String shellQuote(String value) {
  if (RegExp(r'^[A-Za-z0-9_@%+=:,./-]+$').hasMatch(value)) return value;
  return "'${value.replaceAll("'", r"'\''")}'";
}

/// [time]'s UTC calendar date, as YYYY-MM-DD, or [none] when null.
String formatDate(DateTime? time, {String none = 'never'}) =>
    time == null ? none : time.toUtc().toIso8601String().substring(0, 10);

/// [time] as UTC ISO 8601, or null, for `--json` output.
String? jsonTime(DateTime? time) => time?.toUtc().toIso8601String();

/// [account] for `--json` output.
Map<String, Object?> serviceAccountJson(ServiceAccount account) => {
  'id': account.id,
  'name': account.name,
  'label': account.label,
  'role': account.role.value,
  'organization_id': account.organizationId,
  'created_at': jsonTime(account.createdAt),
  'created_by_email': account.createdByEmail,
  'last_auth_at': jsonTime(account.lastAuthAt),
};

/// [account], listed across an enterprise, for `--json` output: the fields
/// of [serviceAccountJson] the enterprise listing has (no `label`), and its
/// organization's [organizationName].
Map<String, Object?> enterpriseServiceAccountJson(
  EnterpriseServiceAccount account, {
  required String? organizationName,
}) => {
  'id': account.userId,
  'name': account.name,
  'role': account.role.value,
  'organization_id': account.teamId,
  'organization_name': organizationName,
  'created_at': jsonTime(account.createdAt),
  'created_by_email': account.createdByEmail,
  'last_auth_at': jsonTime(account.lastAuthAt),
};

/// [key] for `--json` output.
Map<String, Object?> serviceAccountKeyJson(ServiceAccountKey key) => {
  'id': key.id,
  'name': key.name,
  'created_at': jsonTime(key.createdAt),
  'expires_at': jsonTime(key.expiresAt),
  'last_used_at': jsonTime(key.lastUsedAt),
};

/// [key] as one line of human-readable output.
String serviceAccountKeyLine(ServiceAccountKey key) =>
    '${key.id}  ${key.name}  created ${formatDate(key.createdAt)}  '
    'expires ${formatDate(key.expiresAt)}  '
    'last used ${formatDate(key.lastUsedAt)}';
