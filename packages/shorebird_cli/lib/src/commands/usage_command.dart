import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/enterprises/enterprise_scoped_command.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template usage_command}
/// `shorebird usage`
/// Show patch-install usage this allotment period.
/// {@endtemplate}
class UsageCommand extends ShorebirdCommand
    with OrganizationScopedCommand, EnterpriseScopedCommand {
  /// {@macro usage_command}
  UsageCommand() {
    addOrganizationScopeOption();
    addEnterpriseScopeOption(
      help:
          "Show this enterprise's plan (e.g. \"7\") instead: its installs "
          'across every organization, then each organization. Needs an owner '
          'or billing manager of the enterprise.',
    );
  }

  @override
  String get name => 'usage';

  @override
  String get invocation => 'shorebird usage [<org-id>]';

  @override
  String get description =>
      'Shows patch installs this allotment period against your plan.\n\n'
      "Usage counts every app the organization's owner owns. Other members "
      "see only this organization's apps in the list.\n\n"
      'Example output:\n'
      '  Patch installs: 12,345 of 50,000 included\n'
      '  Installs left before patches stop: 37,655\n'
      '  Apps (id  name  installs):\n'
      '    0b6c...  Acme Mobile  12,345\n\n'
      'With --enterprise-id, shows the enterprise plan and each '
      'organization on it (id  name  installs).\n\n'
      '${ShorebirdCommand.jsonHint(
        'shorebird usage 42 --json',
      )}';

  @override
  Future<int> run() async {
    if (enterpriseIdOption != null) {
      final scopeError = rejectOrganizationAndEnterprise();
      if (scopeError != null) return scopeError;
      if (results.rest.isNotEmpty) {
        return reportError(
          message:
              'Pass an organization id or --enterprise-id, not both: '
              '--enterprise-id already covers every organization in the '
              'enterprise.',
        );
      }
      return _enterpriseUsage();
    }
    final (:membership, :errorCode) = await resolveOrganizationFromArguments(
      example: 'shorebird usage <org-id>',
    );
    if (errorCode != null) return errorCode;
    final organizationId = membership!.organization.id;

    late final GetUsageResponse usage;
    final fetchError = await guardApiCall(
      () async => usage = await codePushClientWrapper.getOrganizationUsage(
        organizationId: organizationId,
      ),
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch usage for organization $organizationId.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({'organization_id': organizationId, ...usage.toJson()});
      return ExitCode.success.code;
    }

    final number = NumberFormat.decimalPattern('en_US');
    // The overage fields are null exactly when the plan has no overage
    // billing, so they say which way out the account has.
    final billsOverage =
        usage.position.accruedOverageAmount != null ||
        usage.reportedOverage != null;
    _printPosition(
      usage.position,
      nextStep: billsOverage
          ? 'Raise your overage limit at ${ShorebirdWebConsole.baseUri}.'
          : 'Upgrade your plan at ${ShorebirdWebConsole.baseUri}.',
    );

    if (usage.apps.isEmpty) return ExitCode.success.code;
    logger.info('Apps (id  name  installs):');
    for (final app in usage.apps) {
      logger.info(
        '  ${app.id}  ${lightCyan.wrap(app.name)}  '
        '${number.format(app.patchInstallCount)}',
      );
    }
    return ExitCode.success.code;
  }

  Future<int> _enterpriseUsage() async {
    final (:membership, :errorCode) = await resolveEnterprise();
    if (errorCode != null) return errorCode;
    final enterprise = membership!;

    late final EnterpriseBilling billing;
    late final List<EnterpriseBillingOrganization> organizations;
    final fetchError = await guardApiCall(
      () async {
        billing = await codePushClientWrapper.getEnterpriseBilling(
          enterpriseId: enterprise.id,
        );
        organizations = await codePushClientWrapper
            .getEnterpriseBillingOrganizations(enterpriseId: enterprise.id);
      },
      code: JsonErrorCode.fetchFailed,
      message: 'Failed to fetch usage for enterprise ${enterprise.id}.',
    );
    if (fetchError != null) return fetchError;

    if (isJsonMode) {
      emitJsonSuccess({
        'enterprise_id': enterprise.id,
        ...billing.toJson(),
        'organizations': [for (final org in organizations) org.toJson()],
      });
      return ExitCode.success.code;
    }

    final plan = billing.plan;
    final position = billing.position;
    if (plan == null || position == null) {
      logger.info('"${enterprise.name}" has no billing account.');
      return ExitCode.success.code;
    }
    logger.info(
      'Plan: ${plan.name}, this period ${_day(plan.currentPeriodStart)} to '
      '${_day(plan.currentPeriodEnd)}',
    );
    // A contract sets an enterprise's limits, so there is no setting to
    // point at.
    _printPosition(position, nextStep: null);
    if (organizations.isEmpty) return ExitCode.success.code;
    final number = NumberFormat.decimalPattern('en_US');
    logger.info('Organizations (id  name  installs):');
    for (final org in organizations) {
      logger.info(
        '  ${org.id}  ${lightCyan.wrap(org.name)}  '
        '${number.format(org.patchInstalls)}',
      );
    }
    return ExitCode.success.code;
  }

  /// Prints installs against [position]'s plan, and a warning near or at
  /// its limit, followed by [nextStep] when there is one.
  void _printPosition(AccountPosition position, {required String? nextStep}) {
    final number = NumberFormat.decimalPattern('en_US');
    logger.info(
      'Patch installs: ${number.format(position.installs)} of '
      '${number.format(position.includedInstalls)} included',
    );
    if (position.overageInstalls > 0) {
      final amount = _majorUnits(position.accruedOverageAmount);
      logger.info(
        'Billed as overage: ${number.format(position.overageInstalls)}'
        '${amount == null ? '' : " ($amount so far, in your plan's currency)"}',
      );
    }
    if (position.remainingInstalls case final remaining?) {
      logger.info(
        'Installs left before patches stop: ${number.format(remaining)}',
      );
    }
    final then = nextStep == null ? '' : ' $nextStep';
    if (position.atCeiling) {
      logger.warn(
        'Patches have stopped: the account reached its install limit.$then',
      );
    } else if (position.nearingLimit) {
      logger.warn(
        'The account is nearing its install limit, after which patches '
        'stop.$then',
      );
    }
  }
}

/// [time]'s UTC calendar date, as YYYY-MM-DD.
String _day(DateTime time) => time.toUtc().toIso8601String().substring(0, 10);

/// [minorUnits], an amount in minor units as the API sends it (e.g.
/// "1234.5"), in major units with two decimals (e.g. "12.35"), or null when
/// absent or not a number.
String? _majorUnits(String? minorUnits) {
  final value = minorUnits == null ? null : double.tryParse(minorUnits);
  return value == null ? null : (value / 100).toStringAsFixed(2);
}

/// {@template orgs_usage_command}
/// `shorebird orgs usage`, a hidden alias of `shorebird usage`, for agents
/// that look under the organization noun.
/// {@endtemplate}
class OrgsUsageCommand extends UsageCommand {
  /// {@macro orgs_usage_command}
  OrgsUsageCommand();

  @override
  bool get hidden => true;
}

/// {@template account_usage_command}
/// `shorebird account usage`, a hidden alias of `shorebird usage`, which 6 of
/// 9 agents typed first.
/// {@endtemplate}
class AccountUsageCommand extends UsageCommand {
  /// {@macro account_usage_command}
  AccountUsageCommand();

  @override
  bool get hidden => true;
}
