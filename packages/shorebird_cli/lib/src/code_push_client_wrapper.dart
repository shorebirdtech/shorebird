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
import 'package:shorebird_cli/src/api_error_exit.dart';
import 'package:shorebird_cli/src/archive/directory_archive.dart';
import 'package:shorebird_cli/src/artifact_manager.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/extensions/directory.dart';
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
        hint:
            'Pass --display-name=<name> to set the app name without '
            'prompting.',
      );
    } else {
      displayName = appName;
    }

    return codePushClient.createApp(
      displayName: displayName,
      organizationId: organizationId,
    );
  }

  /// Fetches the currently authenticated user.
  Future<PrivateUser> getCurrentUser() async {
    final user = await _withProgress(
      'Fetching account',
      codePushClient.getCurrentUser,
    );
    if (user == null) {
      logger.err('Could not find current user.');
      throw ProcessExit(ExitCode.software.code);
    }
    return user;
  }

  /// Fetches the plan level for the current user, e.g. `free`, `pro`,
  /// `business` or `enterprise`. Null when the server does not report one.
  Future<String?> getPlanLevel() {
    return _withProgress('Fetching plan', codePushClient.getPlanLevel);
  }

  /// Sets the current user's display name to [displayName].
  Future<void> updateCurrentUser({required String displayName}) {
    return _withProgress(
      'Updating account',
      () => codePushClient.updateCurrentUser(displayName: displayName),
    );
  }

  /// Whether the current user receives email notifications.
  Future<bool> getEmailNotificationsEnabled() {
    return _withProgress(
      'Fetching notification settings',
      codePushClient.getEmailNotificationsEnabled,
    );
  }

  /// Turns the current user's email notifications on or off.
  Future<void> setEmailNotificationsEnabled({required bool enabled}) {
    return _withProgress(
      'Updating notification settings',
      () => codePushClient.setEmailNotificationsEnabled(enabled: enabled),
    );
  }

  /// Fetches the organization memberships for the current user.
  Future<List<OrganizationMembership>> getOrganizationMemberships() {
    return _withProgress(
      'Fetching organizations',
      codePushClient.getOrganizationMemberships,
    );
  }

  /// Fetches the pending invitations sent to the current user.
  Future<List<ReceivedInvitation>> getReceivedInvitations() {
    return _withProgress(
      'Fetching invitations',
      codePushClient.getReceivedInvitations,
    );
  }

  /// Accepts the invitation with [invitationId].
  Future<void> acceptInvitation({required String invitationId}) {
    return _withProgress(
      'Accepting invitation',
      () => codePushClient.acceptInvitation(invitationId: invitationId),
    );
  }

  /// Declines the invitation with [invitationId].
  Future<void> declineInvitation({required String invitationId}) {
    return _withProgress(
      'Declining invitation',
      () => codePushClient.declineInvitation(invitationId: invitationId),
    );
  }

  /// Fetches the apps for the current user.
  Future<List<AppMetadata>> getApps() {
    return _withProgress('Fetching apps', codePushClient.getApps);
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
  ///
  /// This asks the server for the one app rather than downloading the whole
  /// account and filtering locally. `getApps` is unpaginated, so the old
  /// approach cost O(apps on the account) on every `release`, `patch` and
  /// `init` -- on a large account that is megabytes and seconds to resolve an
  /// id the caller already had.
  Future<AppMetadata?> maybeGetApp({required String appId}) async {
    final fetchAppProgress = logger.progress('Fetching app');
    try {
      final app = await codePushClient.getApp(appId: appId);
      fetchAppProgress.complete();
      return app;
    } on CodePushForbiddenException {
      // The app exists but belongs to someone else. Callers surface this the
      // same way as "no such app", which is what the list-and-filter approach
      // did: an app you cannot see simply was not in the list.
      fetchAppProgress.complete();
      return null;
    } catch (error) {
      _handleErrorAndExit(error, progress: fetchAppProgress);
    }
  }

  /// Fetches the channels for the given [appId] and channel [name].
  /// Returns null if a channel does not exist.
  Future<Channel?> maybeGetChannel({
    required String appId,
    required String name,
  }) {
    return _withProgress('Fetching channels', () async {
      final channels = await codePushClient.getChannels(appId: appId);
      return channels.firstWhereOrNull((channel) => channel.name == name);
    });
  }

  /// Fetches all channels for the provided [appId].
  Future<List<Channel>> getChannels({required String appId}) {
    return _withProgress(
      'Fetching channels',
      () => codePushClient.getChannels(appId: appId),
    );
  }

  /// Creates a channel for the provided [appId] with the given [name].
  Future<Channel> createChannel({
    required String appId,
    required String name,
  }) {
    return _withProgress(
      'Creating channel',
      () => codePushClient.createChannel(appId: appId, channel: name),
    );
  }

  /// Deletes the channel with the provided [channelId] from [appId].
  Future<void> deleteChannel({
    required String appId,
    required int channelId,
  }) {
    return _withProgress(
      'Deleting channel',
      () => codePushClient.deleteChannel(appId: appId, channelId: channelId),
    );
  }

  /// Renames the app with the provided [appId] to [displayName].
  Future<void> updateApp({
    required String appId,
    required String displayName,
  }) {
    return _withProgress(
      'Renaming app',
      () => codePushClient.updateApp(appId: appId, displayName: displayName),
    );
  }

  /// Archives the app with the provided [appId]. Devices keep the patch they
  /// have but are offered no new ones, and new releases and patches are
  /// refused until the app is unarchived.
  Future<void> archiveApp({required String appId}) {
    return _withProgress(
      'Archiving app',
      () => codePushClient.archiveApp(appId: appId),
    );
  }

  /// Unarchives the app with the provided [appId], resuming patch serving.
  Future<void> unarchiveApp({required String appId}) {
    return _withProgress(
      'Unarchiving app',
      () => codePushClient.unarchiveApp(appId: appId),
    );
  }

  /// Deletes the app with the provided [appId], along with every release and
  /// patch belonging to it.
  Future<void> deleteApp({required String appId}) {
    return _withProgress(
      'Deleting app',
      () => codePushClient.deleteApp(appId: appId),
    );
  }

  /// Deletes the release with the provided [releaseId], along with every
  /// platform's artifacts and every patch belonging to it.
  Future<void> deleteRelease({required String appId, required int releaseId}) {
    return _withProgress(
      'Deleting release',
      () => codePushClient.deleteRelease(appId: appId, releaseId: releaseId),
    );
  }

  /// Deletes the [platform] artifacts of the release with the provided
  /// [releaseId], leaving the release and its other platforms in place.
  Future<void> deleteReleaseArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
  }) {
    return _withProgress(
      'Deleting ${platform.value} release artifacts',
      () => codePushClient.deleteReleaseArtifacts(
        appId: appId,
        releaseId: releaseId,
        platform: platform,
      ),
    );
  }

  /// Moves the app with the provided [appId] into [organizationId].
  Future<void> transferApp({
    required int organizationId,
    required String appId,
  }) {
    return _withProgress(
      'Transferring app',
      () => codePushClient.transferApp(
        organizationId: organizationId,
        appId: appId,
      ),
    );
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
  }) {
    return _withProgress(
      'Fetching releases',
      () => codePushClient.getReleases(
        appId: appId,
        sideloadableOnly: sideloadableOnly,
      ),
    );
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
  }) {
    return _withProgress(
      'Fetching patches',
      () => codePushClient.getPatches(appId: appId, releaseId: releaseId),
    );
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
  }) {
    return _withProgress(
      'Updating release status',
      () => codePushClient.updateReleaseStatus(
        appId: appId,
        releaseId: releaseId,
        platform: platform,
        status: status,
        metadata: metadata,
      ),
    );
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
  }) {
    return _withProgress('Fetching $arch artifact', () async {
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
      return artifacts.first;
    });
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

    // When the built .aab never packaged libapp.so, surface that directly
    // instead of the generic "cannot find artifacts" or abiFilters messages,
    // which send users down the wrong trail
    // (https://github.com/shorebirdtech/shorebird/issues/3813).
    final missingLibappMessage =
        await ArtifactManager.describeMissingLibappInAab(File(aabPath));
    if (missingLibappMessage != null) {
      _handleErrorAndExit(
        Exception('No architecture artifacts found to upload.'),
        progress: createArtifactProgress,
        message: missingLibappMessage,
      );
    }

    final archsDir = await ArtifactManager.androidArchsDirectoryFromAab(
      projectRoot: Directory(projectRoot),
      flavor: flavor,
      aab: File(aabPath),
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
  - the libapp.so entries inside the built .aab
  - build/app/intermediates/stripped_native_libs/{variant}/strip{Variant}ReleaseDebugSymbols/out/lib
  - build/app/intermediates/stripped_native_libs/{variant}/out/lib''',
      );
    }

    await _uploadAndroidArchArtifacts(
      appId: appId,
      releaseId: releaseId,
      platform: platform,
      archsDir: archsDir.path,
      architectures: architectures,
      progress: createArtifactProgress,
    );

    await _uploadReleaseArtifact(
      appId: appId,
      releaseId: releaseId,
      file: File(aabPath),
      name: 'aab',
      arch: 'aab',
      platform: platform,
      canSideload: true,
      progress: createArtifactProgress,
    );

    createArtifactProgress.complete();
  }

  /// Zips and uploads a Windows release directory.
  Future<void> createWindowsReleaseArtifacts({
    required String appId,
    required int releaseId,
    required Directory releaseDirectory,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final zippedRelease = await releaseDirectory.zipToTempFile();
    try {
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedRelease,
        name: 'Windows release (exe)',
        arch: primaryWindowsReleaseArtifactArch,
        platform: ReleasePlatform.windows,
        canSideload: true,
        progress: createArtifactProgress,
      );
    } finally {
      zippedRelease.parent.deleteTemporarySync();
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

    await _uploadAndroidArchArtifacts(
      appId: appId,
      releaseId: releaseId,
      platform: platform,
      archsDir: p.join(extractedAarDir, 'jni'),
      architectures: architectures,
      progress: createArtifactProgress,
    );

    await _uploadReleaseArtifact(
      appId: appId,
      releaseId: releaseId,
      file: File(aarPath),
      name: 'aar',
      arch: 'aar',
      platform: platform,
      canSideload: false,
      progress: createArtifactProgress,
    );

    createArtifactProgress.complete();
  }

  /// Uploads the libapp.so under [archsDir] for each of [architectures].
  ///
  /// Architectures with no libapp.so are skipped, and the release fails only
  /// if none were uploaded. Shared by the app bundle and archive releases so
  /// both handle ABI filtering the same way.
  Future<void> _uploadAndroidArchArtifacts({
    required String appId,
    required int releaseId,
    required ReleasePlatform platform,
    required String archsDir,
    required Iterable<Arch> architectures,
    required Progress progress,
  }) async {
    // Track which arch paths AGP didn't produce, so we can surface them at
    // the end if zero archs uploaded. AGP omits an arch directory whenever
    // the project filters it out via `ndk.abiFilters`, `splits.abi`, or
    // `jniLibs.excludes`. Iterating only over present files lets a filtered
    // release succeed instead of crashing on the first missing arch
    // (https://github.com/shorebirdtech/shorebird/issues/3388).
    final missingArchPaths = <String>[];
    var uploadedArchCount = 0;
    for (final arch in architectures) {
      final artifactPath = p.join(
        archsDir,
        arch.androidBuildPath,
        'libapp.so',
      );
      final artifact = File(artifactPath);
      if (!artifact.existsSync()) {
        logger.detail(
          'Skipping ${arch.arch}: no libapp.so at $artifactPath. '
          'This is expected if the project filters this ABI via '
          'ndk.abiFilters, splits.abi, or jniLibs.excludes.',
        );
        missingArchPaths.add(artifactPath);
        continue;
      }
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: artifact,
        name: arch.arch,
        arch: arch.arch,
        platform: platform,
        canSideload: false,
        progress: progress,
      );
      uploadedArchCount++;
    }

    if (uploadedArchCount == 0) {
      _handleErrorAndExit(
        Exception('No architecture artifacts found to upload.'),
        progress: progress,
        message:
            '''
No architecture artifacts found to upload.

Shorebird looked for libapp.so under $archsDir but every requested
architecture was missing:
${missingArchPaths.map((p) => '  - $p').join('\n')}

This usually means your project's ndk.abiFilters / splits.abi / jniLibs.excludes
configuration excludes every architecture Shorebird was asked to build. Either
relax those filters or pass `--target-platform=<archs>` to restrict Shorebird
to the architectures your project actually builds.''',
      );
    }
  }

  /// Uploads [file] as the [arch] release artifact for [platform], naming it
  /// [name] in log and error messages.
  ///
  /// The server reuses the artifacts of a release that is not yet active, so a
  /// retried release uploads over them rather than conflicting. A conflict
  /// therefore only means the artifact was just created, and the release can
  /// continue. Every platform handles it the same way. Any other failure fails
  /// [progress] and exits.
  Future<void> _uploadReleaseArtifact({
    required String appId,
    required int releaseId,
    required File file,
    required String name,
    required String arch,
    required ReleasePlatform platform,
    required bool canSideload,
    required Progress progress,
    String? podfileLockHash,
  }) async {
    logger.detail('Uploading $name artifact from ${file.path}');
    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: file.path,
        arch: arch,
        platform: platform,
        hash: sha256.convert(await file.readAsBytes()).toString(),
        canSideload: canSideload,
        podfileLockHash: podfileLockHash,
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info('''

$name artifact already exists, continuing...''');
    } catch (error) {
      _handleErrorAndExit(
        error,
        progress: progress,
        message: 'Error uploading $name artifact: $error',
      );
    }
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
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedBundle,
        name: 'bundle',
        arch: primaryLinuxReleaseArtifactArch,
        platform: ReleasePlatform.linux,
        canSideload: true,
        progress: createArtifactProgress,
      );
    } finally {
      zippedBundle.parent.deleteTemporarySync();
    }

    createArtifactProgress.complete();
  }

  /// Registers and uploads macOS release artifacts to the Shorebird server.
  Future<void> createMacosReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String appPath,
    required String? podfileLockHash,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    final tempDir = await Directory.systemTemp.createTemp();
    try {
      final zippedApp = File(
        p.join(tempDir.path, '${p.basename(appPath)}.zip'),
      );
      await ditto.archive(source: appPath, destination: zippedApp.path);

      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedApp,
        name: 'app',
        arch: 'app',
        platform: ReleasePlatform.macos,
        canSideload: true,
        podfileLockHash: podfileLockHash,
        progress: createArtifactProgress,
      );
    } finally {
      tempDir.deleteTemporarySync();
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
    final File zippedArchive;
    try {
      zippedArchive = await thinnedArchiveDirectory.zipToTempFile();
    } finally {
      thinnedArchiveDirectory.parent.deleteTemporarySync();
    }
    try {
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedArchive,
        name: 'xcarchive',
        arch: 'xcarchive',
        platform: ReleasePlatform.ios,
        canSideload: false,
        podfileLockHash: podfileLockHash,
        progress: createArtifactProgress,
      );
    } finally {
      zippedArchive.parent.deleteTemporarySync();
    }

    final zippedRunner = await Directory(runnerPath).zipToTempFile();
    logger.detail('[archive] zipped runner.app');
    try {
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedRunner,
        name: 'runner.app',
        arch: 'runner',
        platform: ReleasePlatform.ios,
        canSideload: isCodesigned,
        podfileLockHash: podfileLockHash,
        progress: createArtifactProgress,
      );
    } finally {
      zippedRunner.parent.deleteTemporarySync();
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
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedAppFrameworkFile,
        name: 'xcframework',
        arch: 'xcframework',
        platform: ReleasePlatform.ios,
        canSideload: false,
        progress: createArtifactProgress,
      );
    } finally {
      zippedAppFrameworkFile.parent.deleteTemporarySync();
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
      await _uploadReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        file: zippedSupplement,
        name: 'supplement',
        arch: arch,
        platform: platform,
        // Supplements are auxiliary snapshot metadata used during patching and
        // can't produce a working app on their own, so sideloading isn't
        // applicable. They contain only Dart snapshot metadata (e.g. class
        // tables, dispatch tables) and have no dependency on native pods, so
        // no podfile lock hash is passed either.
        canSideload: false,
        progress: createSupplementProgress,
      );
    } finally {
      zippedSupplement.parent.deleteTemporarySync();
    }
    createSupplementProgress.complete();
  }

  /// Creates a patch for the given [appId], [releaseId], and [metadata].
  @visibleForTesting
  Future<Patch> createPatch({
    required String appId,
    required int releaseId,
    required Json metadata,
  }) {
    return _withProgress(
      'Creating patch',
      () => codePushClient.createPatch(
        appId: appId,
        releaseId: releaseId,
        metadata: metadata,
      ),
    );
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
  }) {
    return _withProgress(
      'Promoting patch to ${channel.name}',
      () => codePushClient.promotePatch(
        appId: appId,
        patchId: patchId,
        channelId: channel.id,
      ),
    );
  }

  /// Rolls back the patch identified by [patchId] under [releaseId]. Returns
  /// whether the server changed the patch, which is `false` when it was
  /// already rolled back.
  ///
  /// [patchNumber] is used purely for the human-readable progress message;
  /// pass it through when the caller already has it on hand.
  Future<bool> rollbackPatch({
    required String appId,
    required int releaseId,
    required int patchId,
    int? patchNumber,
  }) async {
    final label = patchNumber != null ? 'patch $patchNumber' : 'patch';
    final progress = logger.progress('Rolling back $label');
    try {
      final changed = await codePushClient.rollbackPatch(
        appId: appId,
        releaseId: releaseId,
        patchId: patchId,
      );
      // A completed spinner would claim the rollback happened, so say so when
      // the server reported there was nothing to change.
      progress.complete(
        changed ? null : 'No change: $label was already rolled back',
      );
      return changed;
    } catch (error) {
      _handleErrorAndExit(error, progress: progress);
    }
  }

  /// Rolls forward (un-rolls-back) the patch identified by [patchId] under
  /// [releaseId], returning it to its active state so the server resends the
  /// same patch artifact to devices on the next patch check. Returns whether
  /// the server changed the patch, which is `false` when it was already
  /// active.
  ///
  /// [patchNumber] is used purely for the human-readable progress message;
  /// pass it through when the caller already has it on hand.
  Future<bool> rollforwardPatch({
    required String appId,
    required int releaseId,
    required int patchId,
    int? patchNumber,
  }) async {
    final label = patchNumber != null ? 'patch $patchNumber' : 'patch';
    final progress = logger.progress('Rolling forward $label');
    try {
      final changed = await codePushClient.rollforwardPatch(
        appId: appId,
        releaseId: releaseId,
        patchId: patchId,
      );
      // A completed spinner would claim the rollforward happened, so say so
      // when the server reported there was nothing to change.
      progress.complete(
        changed ? null : 'No change: $label was already active',
      );
      return changed;
    } catch (error) {
      _handleErrorAndExit(error, progress: progress);
    }
  }

  /// Publishes a patch to the Shorebird server. This consists of creating a
  /// patch, uploading patch artifacts, and promoting the patch to a specific
  /// channel based on the provided [track].
  Future<Patch> publishPatch({
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
    return patch;
  }

  /// Returns a GCP download link for measuring download speed.
  Future<Uri> getGCPDownloadSpeedTestUrl() {
    return codePushClient.getGCPDownloadSpeedTestUrl();
  }

  /// Returns a GCP upload link for measuring upload speed.
  Future<Uri> getGCPUploadSpeedTestUrl() {
    return codePushClient.getGCPUploadSpeedTestUrl();
  }

  /// Runs [body] under a progress spinner showing [message], completing the
  /// spinner on success. Any error fails the spinner and exits with code 70
  /// via [_handleErrorAndExit].
  Future<T> _withProgress<T>(String message, Future<T> Function() body) async {
    final progress = logger.progress(message);
    try {
      final result = await body();
      progress.complete();
      return result;
    } catch (error) {
      _handleErrorAndExit(error, progress: progress);
    }
  }

  /// Prints an appropriate error message for the given error and exits with
  /// code 70. If [progress] is provided, it will be failed with the given
  /// [message] or [error.toString()] if [message] is null.
  ///
  /// A failed API call ([CodePushException]) also logs the server's error
  /// code and exits with an [ApiErrorExit], so `--json` output can report
  /// that code and the server's details.
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

    if (error is CodePushException) {
      if (error.code case final apiCode?) logger.info('Error code: $apiCode');
      throw ApiErrorExit(error, ExitCode.software.code);
    }
    throw ProcessExit(ExitCode.software.code);
  }
}
