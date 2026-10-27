import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// {@template usage_command}
/// `shorebird account usage`
/// Show patch-install usage this allotment period.
/// {@endtemplate}
class UsageCommand extends ShorebirdCommand with OrganizationScopedCommand {
  /// {@macro usage_command}
  UsageCommand() {
    addOrganizationScopeOption();
  }

  @override
  String get name => 'usage';

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
      '${ShorebirdCommand.jsonHint(
        'shorebird account usage --org-id 42 --json',
      )}';

  @override
  Future<int> run() async {
    final (:membership, :errorCode) = await resolveOrganization();
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
    final position = usage.position;
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
    // The overage fields are null exactly when the plan has no overage
    // billing, so they say which way out the account has.
    final billsOverage =
        position.accruedOverageAmount != null || usage.reportedOverage != null;
    final nextStep = billsOverage
        ? 'Raise your overage limit at ${ShorebirdWebConsole.baseUri}.'
        : 'Upgrade your plan at ${ShorebirdWebConsole.baseUri}.';
    if (position.atCeiling) {
      logger.warn(
        'Patches have stopped: the account reached its install limit. '
        '$nextStep',
      );
    } else if (position.nearingLimit) {
      logger.warn(
        'The account is nearing its install limit, after which patches '
        'stop. $nextStep',
      );
    }

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
}

/// [minorUnits], an amount in minor units as the API sends it (e.g.
/// "1234.5"), in major units with two decimals (e.g. "12.35"), or null when
/// absent or not a number.
String? _majorUnits(String? minorUnits) {
  final value = minorUnits == null ? null : double.tryParse(minorUnits);
  return value == null ? null : (value / 100).toStringAsFixed(2);
}

/// {@template top_level_usage_command}
/// `shorebird usage`, a hidden alias of `shorebird account usage`, which 3
/// of 9 agents typed first.
/// {@endtemplate}
class TopLevelUsageCommand extends UsageCommand {
  /// {@macro top_level_usage_command}
  TopLevelUsageCommand();

  @override
  bool get hidden => true;
}
