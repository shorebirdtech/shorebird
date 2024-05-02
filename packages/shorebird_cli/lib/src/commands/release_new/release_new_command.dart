import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/release_new/android_release_pipeline.dart';
import 'package:shorebird_cli/src/commands/release_new/release_pipeline.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform/platform.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// The different types of shorebird releases that can be created.
enum ReleaseType {
  /// An Android archive used in a hybrid app.
  aar,

  /// A full Flutter Android app.
  android,

  /// A full Flutter iOS app.
  ios,

  /// An iOS framework used in a hybrid app.
  iosFramework;

  /// The CLI argument used to specify the release type(s).
  String get cliName {
    switch (this) {
      case ReleaseType.android:
        return 'android';
      case ReleaseType.ios:
        return 'ios';
      case ReleaseType.iosFramework:
        return 'ios-framework';
      case ReleaseType.aar:
        return 'aar';
    }
  }

  /// The platform associated with the release type.
  ReleasePlatform get releasePlatform {
    switch (this) {
      case ReleaseType.aar:
        return ReleasePlatform.android;
      case ReleaseType.android:
        return ReleasePlatform.android;
      case ReleaseType.ios:
        return ReleasePlatform.ios;
      case ReleaseType.iosFramework:
        return ReleasePlatform.ios;
    }
  }
}

/// {@template release_command}
/// Creates a new app release for the specified platform(s).
/// {@endtemplate}
class ReleaseNewCommand extends ShorebirdCommand {
  /// {@macro release_command}
  ReleaseNewCommand() {
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
      ..addOption(
        'flutter-version',
        help: 'The Flutter version to use when building the app (e.g: 3.16.3).',
      )
      ..addOption(
        'android-artifact',
        help:
            '''The type of artifact to generate. Only relevant for Android releases.''',
        allowed: ['aab', 'apk'],
        defaultsTo: 'aab',
        allowedHelp: {
          'aab': 'Android App Bundle',
          'apk': 'Android Package Kit',
        },
      )
      ..addMultiOption(
        'platform',
        abbr: 'p',
        help: 'The platform(s) to to build this release for.',
        allowed: ReleaseType.values.map((e) => e.cliName).toList(),
        // TODO(bryanoltman): uncomment this once https://github.com/dart-lang/args/pull/273 lands
        // mandatory: true.
      )
      ..addOption(
        'release-version',
        help: '''
The version of the associated release (e.g. "1.0.0"). This should be the version
of the iOS app that is using this module.''',
      )
      ..addMultiOption(
        'target-platform',
        help: 'The target platform(s) for which the app is compiled.',
        defaultsTo: Arch.values.map((arch) => arch.targetPlatformCliArg),
        allowed: Arch.values.map((arch) => arch.targetPlatformCliArg),
      );
  }

  @override
  String get description =>
      'Creates a shorebird release for the provided target platforms';

  @override
  String get name => 'release-new';
  // Creating a release consists of the following steps:
  // 1. Verify preconditions
  // 2. Install the target flutter version if necessary
  // 3. Build the app for each target platform
  // 4. Extract the release version from the compiled artifact OR use the
  //    release version provided.
  // 5. Verify the release does not conflict with an existing release.
  // 6. Create a new release in the database.
  @override
  Future<int> run() async {
    final pipelineFutures = (argResults!['platform'] as List<String>)
        .map(
          (platformArg) => ReleaseType.values.firstWhere(
            (target) => target.cliName == platformArg,
          ),
        )
        .map((target) => _getPipeline(target).run());

    try {
      await Future.wait(pipelineFutures);
    } on BuildPipelineException catch (e) {
      logger.err(e.message);
      return e.exitCode.code;
    }

    return ExitCode.success.code;
  }

  ReleasePipeline _getPipeline(ReleaseType target) {
    switch (target) {
      case ReleaseType.android:
        return AndroidReleasePipline(
          argParser: argParser,
          argResults: argResults!,
        );
      case ReleaseType.ios:
        throw UnimplementedError();
      // return IosReleasePipeline(argResults: argResults);
      case ReleaseType.iosFramework:
        throw UnimplementedError();
      // return IosFrameworkReleasePipeline(argResults: argResults);
      case ReleaseType.aar:
        throw UnimplementedError();
      // return AarReleasePipeline(argResults: argResults);
    }
  }
}
