import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:io/io.dart' as io;
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_artifact_bundle}
/// Metadata about a patch artifact that we are about to upload.
/// {@endtemplate}
class PatchArtifactBundle {
  /// {@macro patch_artifact_bundle}
  const PatchArtifactBundle({
    required this.arch,
    required this.path,
    required this.hash,
    required this.size,
  });

  /// The corresponding architecture.
  final String arch;

  /// The path to the artifact.
  final String path;

  /// The artifact hash.
  final String hash;

  /// The size in bytes of the artifact.
  final int size;
}

// A reference to a [CodePushClientWrapper] instance.
ScopedRef<CodePushClientWrapper> codePushClientWrapperRef = create(() {
  return CodePushClientWrapper(
    codePushClient: CodePushClient(
      httpClient: auth.client,
      hostedUri: shorebirdEnv.hostedUri,
    ),
  );
});

// The [CodePushClientWrapper] instance available in the current zone.
CodePushClientWrapper get codePushClientWrapper =>
    read(codePushClientWrapperRef);

/// {@template code_push_client_wrapper}
/// Wraps [CodePushClient] interaction with logging and error handling to
/// reduce the amount of command and command test code.
/// {@endtemplate}
class CodePushClientWrapper {
  /// {@macro code_push_client_wrapper}
  CodePushClientWrapper({required this.codePushClient});

  final CodePushClient codePushClient;

  Future<App> createApp({String? appName}) async {
    late final String displayName;
    if (appName == null) {
      String? defaultAppName;
      try {
        defaultAppName = shorebirdEnv.getPubspecYaml()?.name;
      } catch (_) {}

      displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: defaultAppName,
      );
    } else {
      displayName = appName;
    }

    return codePushClient.createApp(displayName: displayName);
  }

  Future<List<AppMetadata>> getApps() async {
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      final apps = await codePushClient.getApps();
      fetchAppsProgress.complete();
      return apps;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchAppsProgress);
    }
  }

  Future<AppMetadata> getApp({required String appId}) async {
    final app = await maybeGetApp(appId: appId);
    if (app == null) {
      logger.err(
        '''
Could not find app with id: "$appId".
This app may not exist or you may not have permission to view it.''',
      );
      exit(ExitCode.software.code);
    }

    return app;
  }

  Future<AppMetadata?> maybeGetApp({required String appId}) async {
    final apps = await getApps();
    return apps.firstWhereOrNull((a) => a.appId == appId);
  }

  @visibleForTesting
  Future<Channel?> maybeGetChannel({
    required String appId,
    required String name,
  }) async {
    final fetchChannelsProgress = logger.progress('Fetching channels');
    try {
      final channels = await codePushClient.getChannels(appId: appId);
      final channel = channels.firstWhereOrNull(
        (channel) => channel.name == name,
      );
      fetchChannelsProgress.complete();
      return channel;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchChannelsProgress);
    }
  }

  @visibleForTesting
  Future<Channel> createChannel({
    required String appId,
    required String name,
  }) async {
    final createChannelProgress = logger.progress('Creating channel');
    try {
      final channel = await codePushClient.createChannel(
        appId: appId,
        channel: name,
      );
      createChannelProgress.complete();
      return channel;
    } catch (error) {
      _handleErrorAndExit(error, progress: createChannelProgress);
    }
  }

  /// Prints an error message and exits with code 70 if [release] is in an
  /// active state for [platform].
  void ensureReleaseIsNotActive({
    required Release release,
    required ReleasePlatform platform,
  }) {
    if (release.platformStatuses[platform] == ReleaseStatus.active) {
      logger.err(
        '''
It looks like you have an existing ${platform.name} release for version ${lightCyan.wrap(release.version)}.
Please bump your version number and try again.''',
      );
      exit(ExitCode.software.code);
    }
  }

  Future<Release> getRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final release = await maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (release == null) {
      logger.err(
        '''
Release not found: "$releaseVersion"

Patches can only be published for existing releases.
Please create a release using "shorebird release" and try again.
''',
      );
      exit(ExitCode.software.code);
    }

    return release;
  }

  Future<List<Release>> getReleases({
    required String appId,
    bool sideloadableOnly = false,
  }) async {
    final fetchReleasesProgress = logger.progress('Fetching releases');
    try {
      final releases = await codePushClient.getReleases(
        appId: appId,
        sideloadableOnly: sideloadableOnly,
      );
      fetchReleasesProgress.complete();
      return releases;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchReleasesProgress);
    }
  }

  Future<Release?> maybeGetRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final releases = await getReleases(appId: appId);
    return releases.firstWhereOrNull((r) => r.version == releaseVersion);
  }

  Future<Release> createRelease({
    required String appId,
    required String version,
    required String flutterRevision,
    required ReleasePlatform platform,
  }) async {
    final createReleaseProgress = logger.progress('Creating release');
    try {
      final release = await codePushClient.createRelease(
        appId: appId,
        version: version,
        flutterRevision: flutterRevision,
      );
      await codePushClient.updateReleaseStatus(
        appId: appId,
        releaseId: release.id,
        platform: platform,
        status: ReleaseStatus.draft,
      );
      createReleaseProgress.complete();
      return release;
    } catch (error) {
      _handleErrorAndExit(error, progress: createReleaseProgress);
    }
  }

  Future<void> updateReleaseStatus({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required ReleaseStatus status,
  }) async {
    final updateStatusProgress = logger.progress('Updating release status');
    try {
      await codePushClient.updateReleaseStatus(
        appId: appId,
        releaseId: releaseId,
        platform: platform,
        status: status,
      );
      updateStatusProgress.complete();
    } catch (error) {
      _handleErrorAndExit(error, progress: updateStatusProgress);
    }
  }

  Future<Map<Arch, ReleaseArtifact>> getReleaseArtifacts({
    required String appId,
    required int releaseId,
    required Map<Arch, ArchMetadata> architectures,
    required ReleasePlatform platform,
  }) async {
    // TODO(bryanoltman): update this function to only make one call to
    // getReleaseArtifacts.
    final releaseArtifacts = <Arch, ReleaseArtifact>{};
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching release artifacts',
    );
    for (final entry in architectures.entries) {
      try {
        final artifacts = await codePushClient.getReleaseArtifacts(
          appId: appId,
          releaseId: releaseId,
          arch: entry.value.arch,
          platform: platform,
        );
        if (artifacts.isEmpty) {
          throw CodePushNotFoundException(
            message:
                '''No artifact found for architecture ${entry.value.arch} in release $releaseId''',
          );
        }
        releaseArtifacts[entry.key] = artifacts.first;
      } catch (error) {
        _handleErrorAndExit(error, progress: fetchReleaseArtifactProgress);
      }
    }

    fetchReleaseArtifactProgress.complete();
    return releaseArtifacts;
  }

  Future<ReleaseArtifact> getReleaseArtifact({
    required String appId,
    required int releaseId,
    required String arch,
    required ReleasePlatform platform,
  }) async {
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching $arch artifact',
    );
    try {
      final artifacts = await codePushClient.getReleaseArtifacts(
        appId: appId,
        releaseId: releaseId,
        arch: arch,
        platform: platform,
      );
      if (artifacts.isEmpty) {
        throw CodePushNotFoundException(
          message:
              '''No artifact found for architecture $arch in release $releaseId''',
        );
      }
      fetchReleaseArtifactProgress.complete();
      return artifacts.first;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchReleaseArtifactProgress);
    }
  }

  Future<ReleaseArtifact?> maybeGetReleaseArtifact({
    required String appId,
    required int releaseId,
    required String arch,
    required ReleasePlatform platform,
  }) async {
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching $arch artifact',
    );
    try {
      final artifacts = await codePushClient.getReleaseArtifacts(
        appId: appId,
        releaseId: releaseId,
        arch: arch,
        platform: platform,
      );
      if (artifacts.isEmpty) {
        throw CodePushNotFoundException(
          message:
              '''No artifact found for architecture $arch in release $releaseId''',
        );
      }
      fetchReleaseArtifactProgress.complete();
      return artifacts.first;
    } on CodePushNotFoundException {
      fetchReleaseArtifactProgress.complete();
      return null;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchReleaseArtifactProgress);
    }
  }

  Future<void> createAndroidReleaseArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String aabPath,
    required Map<Arch, ArchMetadata> architectures,
    String? flavor,
  }) async {
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
      final hash = sha256.convert(await artifact.readAsBytes()).toString();
      logger.detail('Creating artifact for $artifactPath');

      try {
        await codePushClient.createReleaseArtifact(
          appId: appId,
          releaseId: releaseId,
          artifactPath: artifact.path,
          arch: archMetadata.arch,
          platform: platform,
          hash: hash,
          canSideload: false,
        );
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info(
          '''

${archMetadata.arch} artifact already exists, continuing...''',
        );
      } catch (error) {
        _handleErrorAndExit(
          error,
          progress: createArtifactProgress,
          message: 'Error uploading ${artifact.path}: $error',
        );
      }
    }

    try {
      logger.detail('Creating artifact for $aabPath');
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: aabPath,
        arch: 'aab',
        platform: platform,
        hash: sha256.convert(await File(aabPath).readAsBytes()).toString(),
        canSideload: true,
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info(
        '''

aab artifact already exists, continuing...''',
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading $aabPath: $error',
      );
    }

    createArtifactProgress.complete();
  }

  Future<void> createAndroidArchiveReleaseArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String aarPath,
    required String extractedAarDir,
    required Map<Arch, ArchMetadata> architectures,
  }) async {
    final createArtifactProgress = logger.progress('Creating artifacts');

    for (final archMetadata in architectures.values) {
      final artifactPath = p.join(
        extractedAarDir,
        'jni',
        archMetadata.path,
        'libapp.so',
      );
      final artifact = File(artifactPath);
      final hash = sha256.convert(await artifact.readAsBytes()).toString();
      logger.detail('Creating artifact for $artifactPath');

      try {
        await codePushClient.createReleaseArtifact(
          appId: appId,
          releaseId: releaseId,
          artifactPath: artifact.path,
          arch: archMetadata.arch,
          platform: platform,
          hash: hash,
          canSideload: false,
        );
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info(
          '''

${archMetadata.arch} artifact already exists, continuing...''',
        );
      } catch (error) {
        _handleErrorAndExit(
          error,
          progress: createArtifactProgress,
          message: 'Error uploading ${artifact.path}: $error',
        );
      }
    }

    try {
      logger.detail('Creating artifact for $aarPath');
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: aarPath,
        arch: 'aar',
        platform: platform,
        hash: sha256.convert(await File(aarPath).readAsBytes()).toString(),
        canSideload: false,
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info(
        '''

aar artifact already exists, continuing...''',
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading $aarPath: $error',
      );
    }

    createArtifactProgress.complete();
  }

  /// Removes all .dylib files from the given .xcarchive to reduce the size of
  /// the uploaded artifact.
  Future<Directory> _thinXcarchive({required String xcarchivePath}) async {
    final xcarchiveDirectoryName = p.basename(xcarchivePath);
    final tempDir = Directory.systemTemp.createTempSync();
    final thinnedArchiveDirectory =
        Directory(p.join(tempDir.path, xcarchiveDirectoryName));
    await io.copyPath(xcarchivePath, thinnedArchiveDirectory.path);
    thinnedArchiveDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.dylib')
        .forEach((file) => file.deleteSync());
    return thinnedArchiveDirectory;
  }

  /// Uploads a release .xcarchive and .app to the Shorebird server.
  Future<void> createIosReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String xcarchivePath,
    required String runnerPath,
    required bool isCodesigned,
  }) async {
    final createArtifactProgress = logger.progress('Creating artifacts');
    final thinnedArchiveDirectory =
        await _thinXcarchive(xcarchivePath: xcarchivePath);
    final zippedArchive = await thinnedArchiveDirectory.zipToTempFile();
    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedArchive.path,
        arch: 'xcarchive',
        platform: ReleasePlatform.ios,
        hash: sha256.convert(await zippedArchive.readAsBytes()).toString(),
        canSideload: false,
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading xcarchive: $error',
      );
    }

    final zippedRunner = await Directory(runnerPath).zipToTempFile();
    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedRunner.path,
        arch: 'runner',
        platform: ReleasePlatform.ios,
        hash: sha256.convert(await zippedRunner.readAsBytes()).toString(),
        canSideload: isCodesigned,
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading runner.app: $error',
      );
    }

    createArtifactProgress.complete();
  }

  /// Zips and uploads a release xcframework to the Shorebird server.
  Future<void> createIosFrameworkReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String appFrameworkPath,
  }) async {
    final createArtifactProgress = logger.progress('Creating artifacts');
    final appFrameworkDirectory = Directory(appFrameworkPath);
    await Isolate.run(
      () => ZipFileEncoder().zipDirectory(appFrameworkDirectory),
    );
    final zippedAppFrameworkFile = File('$appFrameworkPath.zip');

    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedAppFrameworkFile.path,
        arch: 'xcframework',
        platform: ReleasePlatform.ios,
        hash: sha256
            .convert(await zippedAppFrameworkFile.readAsBytes())
            .toString(),
        canSideload: false,
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading xcframework: $error',
      );
    }

    createArtifactProgress.complete();
  }

  @visibleForTesting
  Future<Patch> createPatch({
    required String appId,
    required int releaseId,
  }) async {
    final createPatchProgress = logger.progress('Creating patch');
    try {
      final patch = await codePushClient.createPatch(
        appId: appId,
        releaseId: releaseId,
      );
      createPatchProgress.complete();
      return patch;
    } catch (error) {
      _handleErrorAndExit(error, progress: createPatchProgress);
    }
  }

  @visibleForTesting
  Future<void> createPatchArtifacts({
    required String appId,
    required Patch patch,
    required ReleasePlatform platform,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    for (final artifact in patchArtifactBundles.values) {
      try {
        await codePushClient.createPatchArtifact(
          appId: appId,
          patchId: patch.id,
          artifactPath: artifact.path,
          arch: artifact.arch,
          platform: platform,
          hash: artifact.hash,
        );
      } catch (error) {
        _handleErrorAndExit(error, progress: createArtifactProgress);
      }
    }
    createArtifactProgress.complete();
  }

  @visibleForTesting
  Future<void> promotePatch({
    required String appId,
    required int patchId,
    required Channel channel,
  }) async {
    final promotePatchProgress = logger.progress(
      'Promoting patch to ${channel.name}',
    );
    try {
      await codePushClient.promotePatch(
        appId: appId,
        patchId: patchId,
        channelId: channel.id,
      );
      promotePatchProgress.complete();
    } catch (error) {
      _handleErrorAndExit(error, progress: promotePatchProgress);
    }
  }

  Future<void> publishPatch({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String channelName,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final patch = await createPatch(
      appId: appId,
      releaseId: releaseId,
    );

    await createPatchArtifacts(
      appId: appId,
      patch: patch,
      platform: platform,
      patchArtifactBundles: patchArtifactBundles,
    );

    final channel = await maybeGetChannel(
          appId: appId,
          name: channelName,
        ) ??
        await createChannel(
          appId: appId,
          name: channelName,
        );

    await promotePatch(appId: appId, patchId: patch.id, channel: channel);

    logger.success('\n✅ Published Patch ${patch.number}!');
  }

  /// Prints an appropriate error message for the given error and exits with
  /// code 70. If [progress] is provided, it will be failed with the given
  /// [message] or [error.toString()] if [message] is null.
  Never _handleErrorAndExit(
    Object error, {
    Progress? progress,
    String? message,
  }) {
    if (error is CodePushUpgradeRequiredException) {
      progress?.fail();
      logger
        ..err('Your version of shorebird is out of date.')
        ..info(
          '''Run ${lightCyan.wrap('shorebird upgrade')} to get the latest version.''',
        );
    } else if (progress != null) {
      progress.fail(message ?? '$error');
    }

    exit(ExitCode.software.code);
  }
}
