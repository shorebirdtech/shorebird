import 'package:shorebird_cli/src/command_pipeline/command_pipelines.dart';

class BuildAndroidReleaseArtifactsStep extends PipelineStep {
  @override
  Future<PipelineContext> run(PipelineContext context) async {
    final flutterVersionString = await shorebirdFlutter.getVersionAndRevision();

    final buildAppBundleProgress = logger
        .progress('Building app bundle with Flutter $flutterVersionString');
    await artifactBuilder.buildAppBundle(
      flavor: flavor,
      target: target,
      targetPlatforms: architectures,
    );
    buildAppBundleProgress.complete();

    if (generateApk) {
      final buildApkProgress =
          logger.progress('Building APK with Flutter $flutterVersionString');
      await artifactBuilder.buildApk(
        flavor: flavor,
        target: target,
        targetPlatforms: architectures,
      );
      buildApkProgress.complete();
    }

    final projectRoot = shorebirdEnv.getShorebirdProjectRoot()!;
    try {
      return shorebirdAndroidArtifacts.findAab(
        project: projectRoot,
        flavor: flavor,
      );
    } on MultipleArtifactsFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but it generated multiple AABs in the '
        'build directory. ${error.foundArtifacts.map((e) => e.path)}',
      );
    } on ArtifactNotFoundException catch (error) {
      throw ArtifactBuildException(
        'Build succeeded, but could not find the AAB in the build directory. '
        'Expected to find ${error.artifactName}',
      );
    }
    return context;
  }
}
