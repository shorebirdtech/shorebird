import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/commands/orgs/organization_scoped_command.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
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
      logger.info(
        'Billed as overage: ${number.format(position.overageInstalls)}',
      );
    }
    if (position.remainingInstalls case final remaining?) {
      logger.info(
        'Installs left before patches stop: ${number.format(remaining)}',
      );
    }
    if (position.atCeiling) {
      logger.warn(
        'Patches have stopped: the account reached its install limit. '
        'Raise your overage limit or upgrade your plan at '
        'https://console.shorebird.dev.',
      );
    } else if (position.nearingLimit) {
      logger.warn('The account is nearing its install limit.');
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
