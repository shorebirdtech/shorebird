import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/archive_analysis/archive_analysis.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template release_ios_command}
/// `shorebird release ios-preview`
/// Create new app releases for iOS.
/// {@endtemplate}
class ReleaseIosCommand extends ShorebirdCommand
    with ShorebirdBuildMixin, ShorebirdConfigMixin, ShorebirdValidationMixin {
  /// {@macro release_ios_command}
  ReleaseIosCommand({
    super.auth,
    super.codePushClientWrapper,
    super.cache,
    super.validators,
    IpaReader? ipaReader,
  }) : _ipaReader = ipaReader ?? IpaReader() {
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

  final IpaReader _ipaReader;

  @override
  String get description => '''
Builds and submits your iOS app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  String get name => 'ios-preview';

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

    logger.warn(
      '''iOS support is in an experimental state and will not work without Flutter engine changes that have not yet been published.''',
    );

    const platform = 'ios';
    final flavor = results['flavor'] as String?;
    final shorebirdYaml = getShorebirdYaml()!;
    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = await codePushClientWrapper.getApp(appId: appId);

    final buildProgress = logger.progress('Building release');
    try {
      await buildIpa(flavor: flavor);
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build IPA: ${error.message}');
      return ExitCode.software.code;
    } on BuildException catch (error) {
      buildProgress.fail('Failed to build IPA');
      logger.err(error.message);
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final releaseVersionProgress = logger.progress('Getting release version');
    String releaseVersion;
    try {
      final pubspec = getPubspecYaml()!;
      final ipa = _ipaReader.read(
        p.join(
          Directory.current.path,
          'build',
          'ios',
          'ipa',
          '${pubspec.name}.ipa',
        ),
      );
      releaseVersion = ipa.versionNumber;
    } catch (error) {
      releaseVersionProgress.fail(
        'Failed to determine release version: $error',
      );
      return ExitCode.software.code;
    }

    releaseVersionProgress.complete();

    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('($appId)')}''',
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

    final existingRelease = await codePushClientWrapper.maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (existingRelease != null) {
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

    await codePushClientWrapper.createRelease(
      appId: appId,
      version: releaseVersion,
      flutterRevision: shorebirdFlutterRevision,
    );

    logger.success('\n✅ Published Release!');

    return ExitCode.success.code;
  }
}
