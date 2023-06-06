import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/shorebird_code_push_client_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_ios_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_ios_command}
/// `shorebird release ios`
/// Create new app releases for iOS.
/// {@endtemplate}
class ReleaseIosCommand extends ShorebirdCommand
    with
        ShorebirdConfigMixin,
        ShorebirdValidationMixin,
        ShorebirdCodePushClientMixin,
        ShorebirdIosReleaseVersionMixin {
  /// {@macro release_ios_command}
  ReleaseIosCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.cache,
    super.validators,
  }) {
    argParser
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      )
      ..addFlag(
        'force',
        abbr: 'f',
        help: 'Release without confirmation if there are no errors.',
        negatable: false,
      );
  }

  @override
  String get description => '''
Builds and submits your iOS app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  String get name => 'ios';

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkShorebirdInitialized: true,
        checkValidators: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final flavor = results['flavor'] as String?;
    final shorebirdYaml = getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final App? app;
    try {
      app = await getApp(appId: appId, flavor: flavor);
    } catch (_) {
      return ExitCode.software.code;
    }

    if (app == null) {
      logger.err(
        '''
Could not find app with id: "$appId".
Did you forget to run "shorebird init"?''',
      );
      return ExitCode.software.code;
    }

    String releaseVersion;

    try {
      releaseVersion = await determineIosReleaseVersion();
    } catch (error) {
      logger.err('Failed to determine release version: $error');
      return ExitCode.software.code;
    }

    const platform = 'ios';
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(platform)}''',
    ];

    logger.info('''
${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}
${summary.join('\n')}
''');

    final force = results['force'] == true;
    final needConfirmation = !force;
    if (needConfirmation) {
      final confirm = logger.confirm('Would you like to continue?');

      if (!confirm) {
        logger.info('Aborting.');
        return ExitCode.success.code;
      }
    }

    Release? release;
    try {
      release = await getRelease(appId: appId, releaseVersion: releaseVersion);
    } catch (_) {
      return ExitCode.software.code;
    }

    if (release != null) {
      logger.err(
        '''
It looks like you have an existing release for version ${lightCyan.wrap(releaseVersion)}.
Please bump your version number and try again.''',
      );
      return ExitCode.software.code;
    }

    final flutterRevisionProgress = logger.progress(
      'Fetching Flutter revision',
    );
    final String shorebirdFlutterRevision;
    try {
      shorebirdFlutterRevision = await getShorebirdFlutterRevision();
      flutterRevisionProgress.complete();
    } catch (error) {
      flutterRevisionProgress.fail('$error');
      return ExitCode.software.code;
    }

    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

    final createReleaseProgress = logger.progress('Creating release');
    try {
      release = await codePushClient.createRelease(
        appId: app.id,
        version: releaseVersion,
        flutterRevision: shorebirdFlutterRevision,
      );
      createReleaseProgress.complete();
    } catch (error) {
      createReleaseProgress.fail('$error');
      return ExitCode.software.code;
    }

    logger.success('\n✅ Published Release!');

    return ExitCode.success.code;
  }
}
