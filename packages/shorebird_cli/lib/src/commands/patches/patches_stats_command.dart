import 'package:shorebird_cli/src/commands/metrics/metrics_installs_command.dart';

/// {@template patches_stats_command}
/// `shorebird patches stats`, a hidden alias of `shorebird metrics installs`.
///
/// Agents that have never seen Shorebird's docs guess `patches stats` for
/// patch install counts, so it runs the command they meant.
/// {@endtemplate}
class PatchesStatsCommand extends MetricsInstallsCommand {
  @override
  String get name => 'stats';

  @override
  bool get hidden => true;
}
