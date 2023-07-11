import 'dart:async';

import 'package:barbecue/barbecue.dart';
import 'package:intl/intl.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template account_usage_command}
/// `shorebird account usage`
/// Get usage information for your Shorebird account.
/// {@endtemplate}
class AccountUsageCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdValidationMixin {
  @override
  String get description => 'Get usage information for your Shorebird account.';

  @override
  String get name => 'usage';

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(checkUserIsAuthenticated: true);
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final usage = await codePushClientWrapper.getUsage();

    logger
      ..info('📈 Usage')
      ..info(usage.prettyPrint());

    return ExitCode.success.code;
  }
}

extension on GetUsageResponse {
  String prettyPrint() {
    const cellStyle = CellStyle(
      paddingLeft: 1,
      paddingRight: 1,
      borderBottom: true,
      borderTop: true,
      borderLeft: true,
      borderRight: true,
    );
    var totalPatchInstalls = 0;
    for (final appUsage in apps) {
      totalPatchInstalls += appUsage.patchInstallCount;
    }

    final remainingPatchInstalls = patchInstallLimit == null
        ? '∞'
        : '${patchInstallLimit! - totalPatchInstalls}';

    return '''

You are on the ${lightCyan.wrap(plan.name)} plan.

${Table(
      cellStyle: cellStyle,
      header: const TableSection(
        rows: [
          Row(
            cells: [
              Cell('App'),
              Cell('Patch Installs'),
            ],
          )
        ],
      ),
      body: TableSection(
        rows: [
          for (final appUsage in apps)
            Row(
              cells: [
                Cell(appUsage.name),
                Cell('${appUsage.patchInstallCount}'),
              ],
            ),
          Row(
            cells: [
              const Cell('Total'),
              Cell('$totalPatchInstalls'),
            ],
          ),
        ],
      ),
    ).render()}

${styleBold.wrap('${lightCyan.wrap(remainingPatchInstalls)} patch installs remaining in the current billing period.')}

Current Billing Period: ${lightCyan.wrap(DateFormat.yMMMd().format(currentPeriodStart))} - ${lightCyan.wrap(DateFormat.yMMMd().format(currentPeriodEnd))}
Month-to-date cost: ${lightCyan.wrap(currentPeriodCost.toString())}

${styleBold.wrap('*Usage data is not reported in real-time and may be delayed by up to 48 hours.')}''';
  }
}
