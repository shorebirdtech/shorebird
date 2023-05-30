import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/auth_logger_mixin.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/shorebird_yaml.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_create_app_mixin.dart';
import 'package:shorebird_cli/src/shorebird_java_mixin.dart';
import 'package:shorebird_cli/src/shorebird_release_version_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template release_android_command}
/// `shorebird release android`
/// Create new app releases for Android.
/// {@endtemplate}
class ReleaseAndroidCommand extends ShorebirdCommand
    with
        AuthLoggerMixin,
        ShorebirdValidationMixin,
        ShorebirdConfigMixin,
        ShorebirdBuildMixin,
        ShorebirdCreateAppMixin,
        ShorebirdJavaMixin,
        ShorebirdReleaseVersionMixin {
  /// {@macro release_android_command}
  ReleaseAndroidCommand({
    required super.logger,
    super.auth,
    super.cache,
    super.buildCodePushClient,
    super.validators,
    HashFunction? hashFn,
  }) : _hashFn = hashFn ?? ((m) => sha256.convert(m).toString()) {
    argParser
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
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
Builds and submits your Android app to Shorebird.
Shorebird saves the compiled Dart code from your application in order to
make smaller updates to your app.
''';

  @override
  String get name => 'android';

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
      printNeedsAuthInstructions();
      return ExitCode.noUser.code;
    }

    final validationIssues = await runValidators();
    if (validationIssuesContainsError(validationIssues)) {
      logValidationFailure(issues: validationIssues);
      return ExitCode.config.code;
    }

    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final buildProgress = logger.progress('Building release');
    try {
      await buildAppBundle(flavor: flavor, target: target);
      buildProgress.complete();
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    final shorebirdYaml = getShorebirdYaml()!;
    final codePushClient = buildCodePushClient(
      httpClient: auth.client,
      hostedUri: hostedUri,
    );

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

    final appId = shorebirdYaml.getAppId(flavor: flavor);
    final app = apps.firstWhereOrNull((a) => a.id == appId);
    if (app == null) {
      logger.err(
        '''
Could not find app with id: "$appId".
Did you forget to run "shorebird init"?''',
      );
      return ExitCode.software.code;
    }

    final bundleDirPath = p.join('build', 'app', 'outputs', 'bundle');
    final bundlePath = flavor != null
        ? p.join(bundleDirPath, '${flavor}Release', 'app-$flavor-release.aab')
        : p.join(bundleDirPath, 'release', 'app-release.aab');

    final String releaseVersion;
    final detectReleaseVersionProgress = logger.progress(
      'Detecting release version',
    );
    try {
      releaseVersion = await extractReleaseVersionFromAppBundle(bundlePath);
      detectReleaseVersionProgress.complete();
    } catch (error) {
      detectReleaseVersionProgress.fail('$error');
      return ExitCode.software.code;
    }

    const platform = 'android';
    final archNames = architectures.keys.map(
      (arch) => arch.name,
    );
    final summary = [
      '''📱 App: ${lightCyan.wrap(app.displayName)} ${lightCyan.wrap('(${app.id})')}''',
      if (flavor != null) '🍧 Flavor: ${lightCyan.wrap(flavor)}',
      '📦 Release Version: ${lightCyan.wrap(releaseVersion)}',
      '''🕹️  Platform: ${lightCyan.wrap(platform)} ${lightCyan.wrap('(${archNames.join(', ')})')}''',
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
    }

    // TODO(bryanoltman): Consolidate aab and other artifact creation.
    // TODO(bryanoltman): Parallelize artifact creation.
    final createArtifactProgress = logger.progress('Creating artifacts');
    for (final archMetadata in architectures.values) {
      final artifactPath = p.join(
        Directory.current.path,
        'build',
        'app',
        'intermediates',
        'stripped_native_libs',
        flavor != null ? '${flavor}Release' : 'release',
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
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info(
          '''

${archMetadata.arch} artifact already exists, continuing...''',
        );
      } catch (error) {
        createArtifactProgress.fail('$error');
        return ExitCode.software.code;
      }
    }

    try {
      await codePushClient.createReleaseArtifact(
        releaseId: release.id,
        artifactPath: bundlePath,
        arch: 'aab',
        platform: platform,
        hash: _hashFn(await File(bundlePath).readAsBytes()),
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info(
        '''

aab artifact already exists, continuing...''',
      );
    } catch (error) {
      createArtifactProgress.fail('$error');
      return ExitCode.software.code;
    }

    createArtifactProgress.complete();

    logger
      ..success('\n✅ Published Release!')
      ..info('''

Your next step is to upload the app bundle to the Play Store.
${lightCyan.wrap(bundlePath)}

See the following link for more information:    
${link(uri: Uri.parse('https://support.google.com/googleplay/android-developer/answer/9859152?hl=en'))}
''');

    return ExitCode.success.code;
  }
}
