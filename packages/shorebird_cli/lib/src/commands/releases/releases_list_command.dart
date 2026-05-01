import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/extensions/arg_results.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template releases_list_command}
/// `shorebird releases list`
/// List releases for an app.
/// {@endtemplate}
class ReleasesListCommand extends ShorebirdCommand {
  /// {@macro releases_list_command}
  ReleasesListCommand() {
    argParser
      ..addOption(
        CommonArguments.appIdArg.name,
        help: CommonArguments.appIdArg.description,
      )
      ..addOption(
        CommonArguments.flavorArg.name,
        help: 'The product flavor to list releases for (e.g. "prod").',
      )
      ..addOption(
        'platform',
        allowed: ReleasePlatform.values.map((p) => p.value),
        help: 'Filter to releases that have the specified platform.',
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List releases for an app.';

  @override
  Future<int> run() async {
    final explicitAppId = results[CommonArguments.appIdArg.name] as String?;

    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: explicitAppId == null,
      );
    } on PreconditionFailedException catch (error) {
      return error.exitCode.code;
    }

    final flavor = results.findOption(
      CommonArguments.flavorArg.name,
      argParser: argParser,
    );
    final appId =
        explicitAppId ??
        shorebirdEnv.getShorebirdYaml()!.getAppId(flavor: flavor);

    final platformFilter = ReleasePlatform.maybeFromJson(
      results['platform'] as String?,
    );

    final releases = await codePushClientWrapper.getReleases(appId: appId);

    final filtered = platformFilter != null
        ? releases
              .where((r) => r.platformStatuses.containsKey(platformFilter))
              .toList()
        : releases;

    if (isJsonMode) {
      emitJsonSuccess({
        'releases': filtered.map((r) => r.toJson()).toList(),
      });
      return ExitCode.success.code;
    }

    if (filtered.isEmpty) {
      logger.info('No releases found.');
      return ExitCode.success.code;
    }

    for (final release in filtered) {
      final platforms = release.platformStatuses.entries
          .map((e) => '${e.key.value}: ${e.value.value}')
          .join(', ');
      final flutter = release.flutterVersion != null
          ? '  ${release.flutterVersion}'
          : '';
      logger.info('${lightCyan.wrap(release.version)}  $platforms$flutter');
    }

    return ExitCode.success.code;
  }
}
