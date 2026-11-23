import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/command_error.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template flutter_precache_command}
/// `shorebird flutter precache`
/// Install a Flutter version and download the artifacts building with it
/// needs, without building anything.
///
/// It installs what `shorebird release` and `shorebird patch` would install
/// before building: the Flutter checkout and its `flutter precache`
/// artifacts (which include the engine's Maven artifacts in the Gradle cache
/// when an Android SDK is present), and Shorebird's own artifacts for both
/// the pinned and the requested Flutter. A later build with the same Flutter
/// version then downloads none of it. Use it to bake Flutter into a Docker
/// image or a CI cache.
/// {@endtemplate}
class FlutterPrecacheCommand extends ShorebirdCommand {
  /// {@macro flutter_precache_command}
  FlutterPrecacheCommand() {
    argParser.addOption(
      'flutter-version',
      help: '''
The Flutter version to install (e.g: 3.16.3), or a Flutter commit hash.
Defaults to the version this Shorebird uses when building with
--flutter-version=latest.''',
    );
  }

  @override
  String get description =>
      'Install a Flutter version and its build artifacts without building.';

  @override
  String get name => 'precache';

  @override
  Future<int> run() async {
    final revision = await _resolveRevision();
    try {
      await shorebirdFlutter.installRevision(revision: revision);
    } on Exception {
      // installRevision has already reported what failed.
      return ExitCode.software.code;
    }

    // `shorebird release` updates the cache once for the pinned Flutter and
    // again scoped to the one it builds with (aot-tools is per engine
    // revision), so do both.
    await cache.updateAll();
    final targetEnv = shorebirdEnv.copyWith(flutterRevisionOverride: revision);
    await runScoped(
      cache.updateAll,
      values: {shorebirdEnvRef.overrideWith(() => targetEnv)},
    );

    final version =
        await shorebirdFlutter.getVersionForRevision(
          flutterRevision: revision,
        ) ??
        shorebirdFlutter.shortRevisionString(revision);
    logger.info('✅ Flutter $version is installed and precached.');
    return ExitCode.success.code;
  }

  Future<String> _resolveRevision() async {
    final versionOrHash = results['flutter-version'] as String?;
    if (versionOrHash == null || versionOrHash == 'latest') {
      return shorebirdEnv.flutterRevision;
    }

    // Fetch the latest refs so release branch pointers
    // (e.g. flutter_release/3.38.5) are current, as `shorebird release` does.
    await shorebirdFlutter.fetchRemoteRefs();

    final String? revision;
    try {
      revision = await shorebirdFlutter.resolveFlutterRevision(versionOrHash);
    } on Exception catch (error) {
      throw CommandError(
        message:
            'Unable to determine the revision for Flutter $versionOrHash: '
            '$error',
        hint: 'Run: shorebird flutter versions list',
        exitCode: ExitCode.software,
      );
    }
    if (revision == null) {
      throw CommandError(
        message: 'Flutter $versionOrHash is not available to Shorebird.',
        hint: 'Run: shorebird flutter versions list',
        exitCode: ExitCode.software,
      );
    }
    return revision;
  }
}
