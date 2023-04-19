import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/flutter_validation_mixin.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_command}
/// `shorebird release`
/// Create new app releases.
/// {@endtemplate}
class ReleaseCommand extends ShorebirdCommand
    with
        ShorebirdValidationMixin,
        ShorebirdConfigMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin {
  /// {@macro release_command}
  ReleaseCommand({
    required super.logger,
    super.auth,
    super.buildCodePushClient,
    super.validators,
    HashFunction? hashFn,
  }) : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()) {
    argParser
      ..addOption(
        'release-version',
        help: 'The version of the release (e.g. "1.0.0").',
      )
      ..addOption(
        'platform',
        help: 'The platform of the release (e.g. "android").',
        allowed: ['android'],
        allowedHelp: {'android': 'The Android platform.'},
        defaultsTo: 'android',
      );
  }

  @override
  String get description => '''
Builds and submits your app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  String get name => 'release';

  final HashFunction _hashFn;

  @override
  Future<int> run() async {
    if (!isShorebirdInitialized) {
      logger.err(
        'Shorebird is not initialized. Did you run "shorebird init"?',
      );
      return ExitCode.config.code;
    }

    if (!auth.isAuthenticated) {
      logger.err('You must be logged in to release.');
      return ExitCode.noUser.code;
    }

    await logValidationIssues();

    final buildProgress = logger.progress('Building release');
    try {
      await buildAppBundle();
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final pubspecYaml = getPubspecYaml()!;
    final shorebirdYaml = getShorebirdYaml()!;
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );
    final version = pubspecYaml.version!;
    final versionString = version.toString();

    late final List<App> apps;
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      apps = (await codePushClient.getApps())
          .map((a) => App(id: a.appId, displayName: a.displayName))
          .toList();
      fetchAppsProgress.complete();
    } catch (error) {
      fetchAppsProgress.fail('$error');
      return ExitCode.software.code;
    }

    final app = apps.firstWhereOrNull((a) => a.id == shorebirdYaml.appId);
    if (app == null) {
      logger.err(
        '''
Could not find app with id: "${shorebirdYaml.appId}".
Did you forget to run "shorebird init"?''',
      );
      return ExitCode.software.code;
    }

    final releaseVersionArg = results['release-version'] as String?;

    if (releaseVersionArg == null) logger.info('');

    final releaseVersion = releaseVersionArg ??
        logger.prompt(
          'What is the version of this release?',
          defaultValue: versionString,
        );

    final platform = results['platform'] as String;
    final archNames = architectures.keys.map(
      (arch) => arch.name,
    );

    logger.info('''

${styleBold.wrap(lightGreen.wrap('🚀 Ready to create a new release!'))}

📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}
📦 Release Version: ${lightCyan.wrap(releaseVersion)}
🕹️  Platform: ${lightCyan.wrap(platform)} ${lightCyan.wrap('(${archNames.join(', ')})')}
''');

    final confirm = logger.confirm('Would you like to continue?');

    if (!confirm) {
      logger.info('Aborting.');
      return ExitCode.success.code;
    }

    late final List<Release> releases;
    final fetchReleasesProgress = logger.progress('Fetching releases');
    try {
      releases = await codePushClient.getReleases(appId: app.id);
      fetchReleasesProgress.complete();
    } catch (error) {
      fetchReleasesProgress.fail('$error');
      return ExitCode.software.code;
    }

    var release = releases.firstWhereOrNull((r) => r.version == releaseVersion);
    if (release == null) {
      final createReleaseProgress = logger.progress('Creating release');
      try {
        release = await codePushClient.createRelease(
          appId: app.id,
          version: releaseVersion,
        );
        createReleaseProgress.complete();
      } catch (error) {
        createReleaseProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    final createArtifactProgress = logger.progress('Creating artifacts');
    for (final archMetadata in architectures.values) {
      final artifactPath = p.join(
        Directory.current.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        'release',
        'out',
        'lib',
        archMetadata.path,
        'libapp.so',
      );
      final artifact = File(artifactPath);
      final hash = _hashFn(await artifact.readAsBytes());

      try {
        await codePushClient.createReleaseArtifact(
          releaseId: release.id,
          artifactPath: artifact.path,
          arch: archMetadata.arch,
          platform: platform,
          hash: hash,
        );
      } catch (error) {
        createArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    createArtifactProgress.complete();

    logger
      ..success('\n✅ Published Release!')
      ..info('''

Your next step is to upload the app bundle to the Play Store.
${lightCyan.wrap("./build/app/outputs/bundle/release/app-release.aab")}

See the following link for more information:    
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''');

    return ExitCode.success.code;
  }
}
