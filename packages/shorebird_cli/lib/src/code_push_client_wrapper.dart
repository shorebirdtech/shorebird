// cspell:words endtemplate pubspec sideloadable bryanoltman archs sideload
// cspell:words xcarchive codesigned xcframework

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';
import 'package:io/io.dart' as io;
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_web_console.dart';
import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:shorebird_cli/src/version.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// {@template patch_artifact_bundle}
/// Metadata about a patch artifact that we are about to upload.
/// {@endtemplate}
class PatchArtifactBundle extends Equatable {
  /// {@macro patch_artifact_bundle}
  const PatchArtifactBundle({
    required this.arch,
    required this.path,
    required this.hash,
    required this.size,
    this.hashSignature,
    this.podfileLockHash,
  });

  /// The corresponding architecture.
  final String arch;

  /// The path to the artifact.
  final String path;

  /// The artifact hash.
  final String hash;

  /// The size in bytes of the artifact.
  final int size;

  /// The signature of the artifact hash.
  final String? hashSignature;

  /// The hash of the Podfile.lock file, if present and relevant.
  final String? podfileLockHash;

  @override
  List<Object?> get props => [
    arch,
    path,
    hash,
    size,
    hashSignature,
    podfileLockHash,
  ];
}

/// A reference to a [CodePushClientWrapper] instance.
ScopedRef<CodePushClientWrapper> codePushClientWrapperRef = create(() {
  return CodePushClientWrapper(
    codePushClient: CodePushClient(
      httpClient: auth.client,
      hostedUri: shorebirdEnv.hostedUri,
      customHeaders: {'x-cli-version': packageVersion},
    ),
  );
});

/// The [CodePushClientWrapper] instance available in the current zone.
CodePushClientWrapper get codePushClientWrapper =>
    read(codePushClientWrapperRef);

/// {@template code_push_client_wrapper}
/// Wraps [CodePushClient] interaction with logging and error handling to
/// reduce the amount of command and command test code.
/// {@endtemplate}
class CodePushClientWrapper {
  /// {@macro code_push_client_wrapper}
  CodePushClientWrapper({required this.codePushClient});

  /// The underlying code push client.
  final CodePushClient codePushClient;

  /// Create an app with the given [organizationId] and [appName].
  Future<App> createApp({required int organizationId, String? appName}) async {
    late final String displayName;
    if (appName == null) {
      final defaultAppName = shorebirdEnv.getPubspecYaml()?.name;
      displayName = logger.prompt(
        '${lightGreen.wrap('?')} How should we refer to this app?',
        defaultValue: defaultAppName,
      );
    } else {
      displayName = appName;
    }

    return codePushClient.createApp(
      displayName: displayName,
      organizationId: organizationId,
    );
  }

  /// Fetches the organization memberships for the current user.
  Future<List<OrganizationMembership>> getOrganizationMemberships() async {
    final progress = logger.progress('Fetching organizations');
    final List<OrganizationMembership> memberships;
    try {
      memberships = await codePushClient.getOrganizationMemberships();
      progress.complete();
    } catch (error) {
      _handleErrorAndExit(error, progress: progress);
    }

    return memberships;
  }

  /// Fetches the apps for the current user.
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

  /// Returns [AppMetadata] for the provided [appId].
  Future<AppMetadata> getApp({required String appId}) async {
    final app = await maybeGetApp(appId: appId);
    if (app == null) {
      logger.err('''
Could not find app with id: "$appId".
This app may not exist or you may not have permission to view it.''');

      throw ProcessExit(ExitCode.software.code);
    }

    return app;
  }

  /// Returns [AppMetadata] for the provided [appId] or null if the app does not
  /// exist.
  Future<AppMetadata?> maybeGetApp({required String appId}) async {
    final apps = await getApps();
    return apps.firstWhereOrNull((a) => a.appId == appId);
  }

  /// Fetches the channels for the given [appId] and channel [name].
  /// Returns null if a channel does not exist.
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

  /// Creates a channel for the provided [appId] with the given [name].
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
      final uri = ShorebirdWebConsole.appReleaseUri(release.appId, release.id);
      logger.err(
        '''
It looks like you have an existing ${platform.name} release for version ${lightCyan.wrap(release.version)}.
Please bump your version number and try again.

You can manage this release in the ${link(uri: uri, message: 'Shorebird Console')}''',
      );
      throw ProcessExit(ExitCode.software.code);
    }
  }

  /// Fetches the release for the given [appId] and [releaseVersion].
  Future<Release> getRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final release = await maybeGetRelease(
      appId: appId,
      releaseVersion: releaseVersion,
    );

    if (release == null) {
      logger.err('''
Release not found: "$releaseVersion"

Patches can only be published for existing releases.
Please create a release using "shorebird release" and try again.
''');
      throw ProcessExit(ExitCode.software.code);
    }

    return release;
  }

  /// Fetches the releases for the given [appId].
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

  /// Fetches the release for the given [appId] and [releaseVersion] or null if
  /// the release does not exist.
  Future<Release?> maybeGetRelease({
    required String appId,
    required String releaseVersion,
  }) async {
    final releases = await getReleases(appId: appId);
    return releases.firstWhereOrNull((r) => r.version == releaseVersion);
  }

  /// Gets the patches for [appId]'s [releaseId].
  Future<List<ReleasePatch>> getReleasePatches({
    required String appId,
    required int releaseId,
  }) async {
    final fetchReleasePatchesProgress = logger.progress('Fetching patches');
    try {
      final patches = await codePushClient.getPatches(
        appId: appId,
        releaseId: releaseId,
      );
      fetchReleasePatchesProgress.complete();
      return patches;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchReleasePatchesProgress);
    }
  }

  /// Creates a release for the given [appId], [version], [flutterRevision], and
  /// [platform].
  Future<Release> createRelease({
    required String appId,
    required String version,
    required String flutterRevision,
    required ReleasePlatform platform,
  }) async {
    final createReleaseProgress = logger.progress('Creating release');
    final flutterVersion = await shorebirdFlutter.getVersionForRevision(
      flutterRevision: flutterRevision,
    );
    try {
      final release = await codePushClient.createRelease(
        appId: appId,
        version: version,
        flutterRevision: flutterRevision,
        flutterVersion: flutterVersion,
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

  /// Updates the status of a release for the given [appId], [releaseId],
  /// [platform], and [status].
  Future<void> updateReleaseStatus({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required ReleaseStatus status,
    Json? metadata,
  }) async {
    final updateStatusProgress = logger.progress('Updating release status');
    try {
      await codePushClient.updateReleaseStatus(
        appId: appId,
        releaseId: releaseId,
        platform: platform,
        status: status,
        metadata: metadata,
      );
      updateStatusProgress.complete();
    } catch (error) {
      _handleErrorAndExit(error, progress: updateStatusProgress);
    }
  }

  /// Returns release artifacts for the given [appId], [releaseId],
  /// [architectures], and [platform]. Not all architectures may have artifacts,
  /// so the returned map may not contain all the requested architectures.
  Future<Map<Arch, ReleaseArtifact>> getReleaseArtifacts({
    required String appId,
    required int releaseId,
    required Iterable<Arch> architectures,
    required ReleasePlatform platform,
  }) async {
    // TODO(bryanoltman): update this function to only make one call to
    // getReleaseArtifacts.
    final releaseArtifacts = <Arch, ReleaseArtifact>{};
    final fetchReleaseArtifactProgress = logger.progress(
      'Fetching release artifacts',
    );
    for (final arch in architectures) {
      try {
        final artifacts = await codePushClient.getReleaseArtifacts(
          appId: appId,
          releaseId: releaseId,
          arch: arch.arch,
          platform: platform,
        );
        if (artifacts.isEmpty) {
          continue;
        }
        releaseArtifacts[arch] = artifacts.first;
      } catch (error) {
        _handleErrorAndExit(error, progress: fetchReleaseArtifactProgress);
      }
    }

    fetchReleaseArtifactProgress.complete();
    return releaseArtifacts;
  }

  /// Returns a release artifact for the given [appId], [releaseId], [arch], and
  /// [platform].
  /// Throws a [CodePushNotFoundException] if no artifact is found.
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

  /// Fetches a release artifact for the given [appId], [releaseId], [arch], and
  /// [platform]. Returns null if no artifact is found.
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

  /// Uploads android release artifacts for a specific app/release combination.
  Future<void> createAndroidReleaseArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String projectRoot,
    required String aabPath,
    required Iterable<Arch> architectures,
    String? flavor,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final archsDir = ArtifactManager.androidArchsDirectory(
      projectRoot: Directory(projectRoot),
      flavor: flavor,
    );

    if (archsDir == null) {
      _handleErrorAndExit(
        Exception('Cannot find patch build artifacts.'),
        progress: createArtifactProgress,
        message: '''
Cannot find release build artifacts.

Please run `shorebird cache clean` and try again. If the issue persists, please
file a bug report at https://github.com/shorebirdtech/shorebird/issues/new.

Looked in:
  - build/app/intermediates/stripped_native_libs/stripReleaseDebugSymbols/release/out/lib
  - build/app/intermediates/stripped_native_libs/strip{flavor}ReleaseDebugSymbols/{flavor}Release/out/lib
  - build/app/intermediates/stripped_native_libs/release/out/lib
  - build/app/intermediates/stripped_native_libs/{flavor}Release/out/lib''',
      );
    }

    for (final arch in architectures) {
      final artifactPath = p.join(
        archsDir.path,
        arch.androidBuildPath,
        'libapp.so',
      );
      final artifact = File(artifactPath);
      final hash = sha256.convert(await artifact.readAsBytes()).toString();
      logger.detail('Uploading artifact for $artifactPath');

      try {
        await codePushClient.createReleaseArtifact(
          appId: appId,
          releaseId: releaseId,
          artifactPath: artifact.path,
          arch: arch.arch,
          platform: platform,
          hash: hash,
          canSideload: false,
          podfileLockHash: null,
        );
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info('''

${arch.arch} artifact already exists, continuing...''');
      } catch (error) {
        _handleErrorAndExit(
          error,
          progress: createArtifactProgress,
          message: 'Error uploading ${artifact.path}: $error',
        );
      }
    }

    try {
      logger.detail('Uploading artifact for $aabPath');
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: aabPath,
        arch: 'aab',
        platform: platform,
        hash: sha256.convert(await File(aabPath).readAsBytes()).toString(),
        canSideload: true,
        podfileLockHash: null,
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info('''

aab artifact already exists, continuing...''');
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading $aabPath: $error',
      );
    }

    createArtifactProgress.complete();
  }

  /// Uploads windows release artifacts for a specific app/release combination.
  Future<void> createWindowsReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String projectRoot,
    required String releaseZipPath,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');

    try {
      // logger.detail('Uploading artifact for $aabPath');
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: releaseZipPath,
        arch: primaryWindowsReleaseArtifactArch,
        platform: ReleasePlatform.windows,
        hash: sha256
            .convert(await File(releaseZipPath).readAsBytes())
            .toString(),
        canSideload: true,
        podfileLockHash: null,
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info('''

Windows release (exe) artifact already exists, continuing...''');
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading: $error',
      );
    }
    createArtifactProgress.complete();
  }

  /// Uploads android archive release artifacts for a specific app/release combination.
  Future<void> createAndroidArchiveReleaseArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String aarPath,
    required String extractedAarDir,
    required Iterable<Arch> architectures,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');

    for (final arch in architectures) {
      final artifactPath = p.join(
        extractedAarDir,
        'jni',
        arch.androidBuildPath,
        'libapp.so',
      );
      final artifact = File(artifactPath);
      final hash = sha256.convert(await artifact.readAsBytes()).toString();
      logger.detail('Uploading artifact for $artifactPath');

      try {
        await codePushClient.createReleaseArtifact(
          appId: appId,
          releaseId: releaseId,
          artifactPath: artifact.path,
          arch: arch.arch,
          platform: platform,
          hash: hash,
          canSideload: false,
          podfileLockHash: null,
        );
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info('''

${arch.arch} artifact already exists, continuing...''');
      } catch (error) {
        _handleErrorAndExit(
          error,
          progress: createArtifactProgress,
          message: 'Error uploading ${artifact.path}: $error',
        );
      }
    }

    try {
      logger.detail('Uploading artifact for $aarPath');
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: aarPath,
        arch: 'aar',
        platform: platform,
        hash: sha256.convert(await File(aarPath).readAsBytes()).toString(),
        canSideload: false,
        podfileLockHash: null,
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info('''

aar artifact already exists, continuing...''');
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
    final thinnedArchiveDirectory = Directory(
      p.join(tempDir.path, xcarchiveDirectoryName),
    );
    await io.copyPath(xcarchivePath, thinnedArchiveDirectory.path);
    thinnedArchiveDirectory
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => p.extension(file.path) == '.dylib')
        .forEach((file) => file.deleteSync());
    return thinnedArchiveDirectory;
  }

  /// Zips and uploads a Linux release bundle.
  Future<void> createLinuxReleaseArtifacts({
    required String appId,
    required int releaseId,
    required Directory bundle,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final zippedBundle = await Directory(bundle.path).zipToTempFile();
    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedBundle.path,
        arch: primaryLinuxReleaseArtifactArch,
        platform: ReleasePlatform.linux,
        hash: sha256.convert(await zippedBundle.readAsBytes()).toString(),
        canSideload: true,
        podfileLockHash: null,
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading bundle: $error',
      );
    }

    createArtifactProgress.complete();
  }

  /// Registers and uploads macOS release artifacts to the Shorebird server.
  Future<void> createMacosReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String appPath,
    required bool isCodesigned,
    required String? podfileLockHash,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final tempDir = await Directory.systemTemp.createTemp();
    final zippedApp = File(p.join(tempDir.path, '${p.basename(appPath)}.zip'));
    await ditto.archive(source: appPath, destination: zippedApp.path);

    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedApp.path,
        arch: 'app',
        platform: ReleasePlatform.macos,
        hash: sha256.convert(await zippedApp.readAsBytes()).toString(),
        canSideload: true,
        podfileLockHash: podfileLockHash,
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createArtifactProgress,
        message: 'Error uploading app: $error',
      );
    }

    createArtifactProgress.complete();
  }

  /// Uploads a release .xcarchive, .app, and supplementary files to the
  /// Shorebird server.
  Future<void> createIosReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String xcarchivePath,
    required String runnerPath,
    required bool isCodesigned,
    required String? podfileLockHash,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final thinnedArchiveDirectory = await _thinXcarchive(
      xcarchivePath: xcarchivePath,
    );
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
        podfileLockHash: podfileLockHash,
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
      logger.detail('[archive] zipped runner.app to ${zippedRunner.path}');
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedRunner.path,
        arch: 'runner',
        platform: ReleasePlatform.ios,
        hash: sha256.convert(await zippedRunner.readAsBytes()).toString(),
        canSideload: isCodesigned,
        podfileLockHash: podfileLockHash,
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

  /// Zips and uploads a release xcframework and supplementary files to the
  /// Shorebird server.
  Future<void> createIosFrameworkReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String appFrameworkPath,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final appFrameworkDirectory = Directory(appFrameworkPath);
    final zippedAppFrameworkFile = await appFrameworkDirectory.zipToTempFile();
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
        podfileLockHash: null,
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

  /// Zips and uploads a supplement directory as a release artifact.
  Future<void> createSupplementReleaseArtifact({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String supplementDirectoryPath,
    required String arch,
  }) async {
    final createSupplementProgress = logger.progress(
      'Uploading supplement artifacts',
    );
    final zippedSupplement = await Directory(
      supplementDirectoryPath,
    ).zipToTempFile(name: arch);
    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: zippedSupplement.path,
        arch: arch,
        platform: platform,
        hash: sha256.convert(await zippedSupplement.readAsBytes()).toString(),
        // Supplements are auxiliary snapshot metadata used during patching and
        // can't produce a working app on their own, so sideloading isn't
        // applicable.
        canSideload: false,
        // Supplement artifacts contain only Dart snapshot metadata (e.g. class
        // tables, dispatch tables) and have no dependency on native pods, so
        // the podfile lock hash is not applicable here.
        podfileLockHash: null,
      );
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: createSupplementProgress,
        message: 'Error uploading supplement artifacts: $error',
      );
    }
    createSupplementProgress.complete();
  }

  /// Creates a patch for the given [appId], [releaseId], and [metadata].
  @visibleForTesting
  Future<Patch> createPatch({
    required String appId,
    required int releaseId,
    required Json metadata,
  }) async {
    final createPatchProgress = logger.progress('Creating patch');
    try {
      final patch = await codePushClient.createPatch(
        appId: appId,
        releaseId: releaseId,
        metadata: metadata,
      );
      createPatchProgress.complete();
      return patch;
    } catch (error) {
      _handleErrorAndExit(error, progress: createPatchProgress);
    }
  }

  /// Uploads patch artifacts for a specific app/patch combination.
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
          hashSignature: artifact.hashSignature,
          podfileLockHash: artifact.podfileLockHash,
        );
      } catch (error) {
        _handleErrorAndExit(error, progress: createArtifactProgress);
      }
    }
    createArtifactProgress.complete();
  }

  /// Promotes a patch to a specific [channel].
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

  /// Publishes a patch to the Shorebird server. This consists of creating a
  /// patch, uploading patch artifacts, and promoting the patch to a specific
  /// channel based on the provided [track].
  Future<void> publishPatch({
    required String appId,
    required int releaseId,
    required Json metadata,
    required ReleasePlatform platform,
    required DeploymentTrack track,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final patch = await createPatch(
      appId: appId,
      releaseId: releaseId,
      metadata: metadata,
    );

    await createPatchArtifacts(
      appId: appId,
      patch: patch,
      platform: platform,
      patchArtifactBundles: patchArtifactBundles,
    );

    final channel =
        await maybeGetChannel(appId: appId, name: track.channel) ??
        await createChannel(appId: appId, name: track.channel);

    await promotePatch(appId: appId, patchId: patch.id, channel: channel);

    logger.success('\n✅ Published Patch ${patch.number}!');
  }

  /// Returns a GCP download link for measuring download speed.
  Future<Uri> getGCPDownloadSpeedTestUrl() {
    return codePushClient.getGCPDownloadSpeedTestUrl();
  }

  /// Returns a GCP upload link for measuring upload speed.
  Future<Uri> getGCPUploadSpeedTestUrl() {
    return codePushClient.getGCPUploadSpeedTestUrl();
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

    throw ProcessExit(ExitCode.software.code);
  }
}
