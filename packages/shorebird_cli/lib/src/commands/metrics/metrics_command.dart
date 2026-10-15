import 'package:shorebird_cli/src/commands/metrics/metrics.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template metrics_command}
/// `shorebird metrics`
/// Commands for viewing app install, adoption and usage metrics.
/// {@endtemplate}
class MetricsCommand extends ShorebirdCommand {
  /// {@macro metrics_command}
  MetricsCommand() {
    addSubcommand(MetricsActiveHoursCommand());
    addSubcommand(MetricsAdoptionCommand());
    addSubcommand(MetricsDownloadsCommand());
    addSubcommand(MetricsHeatmapCommand());
    addSubcommand(MetricsInstallsCommand());
    addSubcommand(MetricsNewDevicesCommand());
    addSubcommand(MetricsUsersCommand());
    addSubcommand(MetricsVersionsCommand());
  }

  @override
  String get name => 'metrics';

  @override
  String get description =>
      'View patch install, adoption and usage metrics for an app. '
      'The Shorebird web console shows these as "Insights".';
}
