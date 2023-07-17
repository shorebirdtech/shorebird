import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/auth/auth.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_environment.dart';
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
      hostedUri: ShorebirdEnvironment.hostedUri,
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

  Future<List<AppMetadata>> getApps() async {
    final fetchAppsProgress = logger.progress('Fetching apps');
    try {
      final apps = await codePushClient.getApps();
      fetchAppsProgress.complete();
      return apps;
    } catch (error) {
      fetchAppsProgress.fail('$error');
      exit(ExitCode.software.code);
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
      fetchChannelsProgress.fail('$error');
      exit(ExitCode.software.code);
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
      createChannelProgress.fail('$error');
      exit(ExitCode.software.code);
    }
  }

  /// Exits if [platform] release artifacts already exist for an
  /// [existingRelease].
  Future<void> ensureReleaseHasNoArtifacts({
    required String appId,
    required Release existingRelease,
    required String platform,
  }) async {
    logger.detail('Verifying ability to release');

    final artifacts = await codePushClient.getReleaseArtifacts(
      appId: appId,
      releaseId: existingRelease.id,
      platform: platform,
    );

    logger.detail(
      '''
Artifacts for release:${existingRelease.version} platform:$platform
  $artifacts''',
    );

    if (artifacts.isNotEmpty) {
      logger.err(
        '''
It looks like you have an existing $platform release for version ${lightCyan.wrap(existingRelease.version)}.
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

  Future<List<Release>> getReleases({required String appId}) async {
    final fetchReleasesProgress = logger.progress('Fetching releases');
    try {
      final releases = await codePushClient.getReleases(appId: appId);
      fetchReleasesProgress.complete();
      return releases;
    } catch (error) {
      fetchReleasesProgress.fail('$error');
      exit(ExitCode.software.code);
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
  }) async {
    final createReleaseProgress = logger.progress('Creating release');
    try {
      final release = await codePushClient.createRelease(
        appId: appId,
        version: version,
        flutterRevision: flutterRevision,
      );
      createReleaseProgress.complete();
      return release;
    } catch (error) {
      createReleaseProgress.fail('$error');
      exit(ExitCode.software.code);
    }
  }

  Future<Map<Arch, ReleaseArtifact>> getReleaseArtifacts({
    required String appId,
    required int releaseId,
    required Map<Arch, ArchMetadata> architectures,
    required String platform,
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
        fetchReleaseArtifactProgress.fail('$error');
        exit(ExitCode.software.code);
      }
    }

    fetchReleaseArtifactProgress.complete();
    return releaseArtifacts;
  }

  Future<ReleaseArtifact> getReleaseArtifact({
    required String appId,
    required int releaseId,
    required String arch,
    required String platform,
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
      fetchReleaseArtifactProgress.fail('$error');
      exit(ExitCode.software.code);
    }
  }

  Future<ReleaseArtifact?> maybeGetReleaseArtifact({
    required String appId,
    required int releaseId,
    required String arch,
    required String platform,
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
      fetchReleaseArtifactProgress.fail('$error');
      exit(ExitCode.software.code);
    }
  }

  Future<void> createAndroidReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String platform,
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
        );
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info(
          '''

${archMetadata.arch} artifact already exists, continuing...''',
        );
      } catch (error) {
        createArtifactProgress.fail('Error uploading ${artifact.path}: $error');
        exit(ExitCode.software.code);
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
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info(
        '''

aab artifact already exists, continuing...''',
      );
    } catch (error) {
      createArtifactProgress.fail('Error uploading $aabPath: $error');
      exit(ExitCode.software.code);
    }

    createArtifactProgress.complete();
  }

  Future<void> createAndroidArchiveReleaseArtifacts({
    required String appId,
    required int releaseId,
    required String platform,
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
        );
      } on CodePushConflictException catch (_) {
        // Newlines are due to how logger.info interacts with logger.progress.
        logger.info(
          '''

${archMetadata.arch} artifact already exists, continuing...''',
        );
      } catch (error) {
        createArtifactProgress.fail('Error uploading ${artifact.path}: $error');
        exit(ExitCode.software.code);
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
      );
    } on CodePushConflictException catch (_) {
      // Newlines are due to how logger.info interacts with logger.progress.
      logger.info(
        '''

aar artifact already exists, continuing...''',
      );
    } catch (error) {
      createArtifactProgress.fail('Error uploading $aarPath: $error');
      exit(ExitCode.software.code);
    }

    createArtifactProgress.complete();
  }

  /// Uploads a release ipa to the Shorebird server.
  Future<void> createIosReleaseArtifact({
    required String appId,
    required int releaseId,
    required String ipaPath,
  }) async {
    final createArtifactProgress = logger.progress('Creating artifacts');
    final ipaFile = File(ipaPath);
    try {
      await codePushClient.createReleaseArtifact(
        appId: appId,
        releaseId: releaseId,
        artifactPath: ipaPath,
        arch: 'ipa',
        platform: 'ios',
        hash: sha256.convert(await ipaFile.readAsBytes()).toString(),
      );
    } catch (error) {
      createArtifactProgress.fail('Error uploading ipa: $error');
      exit(ExitCode.software.code);
    }

    createArtifactProgress.complete();
  }

  /// Updates the specified release's status to [ReleaseStatus.active] for the
  /// given platform.
  Future<void> completeRelease({
    required String appId,
    required int releaseId,
    required String platform,
  }) async {
    final completeReleaseProgress = logger.progress('Completing release');
    try {
      await codePushClient.updateReleaseStatus(
        appId: appId,
        releaseId: releaseId,
        status: ReleaseStatus.active,
        platform: platform,
      );
    } catch (error) {
      completeReleaseProgress.fail('$error');
      exit(ExitCode.software.code);
    }
    completeReleaseProgress.complete();
  }

  @visibleForTesting
  Future<Patch> createPatch({required int releaseId}) async {
    final createPatchProgress = logger.progress('Creating patch');
    try {
      final patch = await codePushClient.createPatch(releaseId: releaseId);
      createPatchProgress.complete();
      return patch;
    } catch (error) {
      createPatchProgress.fail('$error');
      exit(ExitCode.software.code);
    }
  }

  @visibleForTesting
  Future<void> createPatchArtifacts({
    required Patch patch,
    required String platform,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final createArtifactProgress = logger.progress('Uploading artifacts');
    for (final artifact in patchArtifactBundles.values) {
      try {
        await codePushClient.createPatchArtifact(
          patchId: patch.id,
          artifactPath: artifact.path,
          arch: artifact.arch,
          platform: platform,
          hash: artifact.hash,
        );
      } catch (error) {
        createArtifactProgress.fail('$error');
        exit(ExitCode.software.code);
      }
    }
    createArtifactProgress.complete();
  }

  @visibleForTesting
  Future<void> promotePatch({
    required int patchId,
    required Channel channel,
  }) async {
    final promotePatchProgress = logger.progress(
      'Promoting patch to ${channel.name}',
    );
    try {
      await codePushClient.promotePatch(
        patchId: patchId,
        channelId: channel.id,
      );
      promotePatchProgress.complete();
    } catch (error) {
      promotePatchProgress.fail('$error');
      exit(ExitCode.software.code);
    }
  }

  Future<void> publishPatch({
    required String appId,
    required int releaseId,
    required String platform,
    required String channelName,
    required Map<Arch, PatchArtifactBundle> patchArtifactBundles,
  }) async {
    final patch = await createPatch(
      releaseId: releaseId,
    );

    await createPatchArtifacts(
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

    await promotePatch(patchId: patch.id, channel: channel);
  }

  Future<GetUsageResponse> getUsage() async {
    final progress = logger.progress('Fetching usage');
    try {
      final usage = await codePushClient.getUsage();
      progress.complete();
      return usage;
    } catch (error) {
      progress.fail(error.toString());
      exit(ExitCode.software.code);
    }
  }
}
