import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/release_new/android_release_pipeline.dart';
import 'package:shorebird_cli/src/commands/release_new/release_pipeline.dart';
import 'package:shorebird_cli/src/platform/platform.dart';

///
enum ReleaseTarget {
  android,
  ios,
  iosFramework,
  aar;

  String get cliName {
    switch (this) {
      case ReleaseTarget.android:
        return 'android';
      case ReleaseTarget.ios:
        return 'ios';
      case ReleaseTarget.iosFramework:
        return 'ios-framework';
      case ReleaseTarget.aar:
        return 'aar';
    }
  }
}

/// {@template release_command}
/// Creates a new app releases for the specified platform(s).
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
        'artifact',
        help: 'They type of artifact to generate.',
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
        help: 'TODO',
        allowed: ReleaseTarget.values.map((e) => e.cliName).toList(),
        // mandatory: true,
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
          (platformArg) => ReleaseTarget.values.firstWhere(
            (target) => target.cliName == platformArg,
          ),
        )
        .map(_getPipeline)
        .map((pipeline) => pipeline.run());

    await Future.wait(pipelineFutures);

    return ExitCode.success.code;
  }

  ReleasePipeline _getPipeline(ReleaseTarget target) {
    switch (target) {
      case ReleaseTarget.android:
        return AndroidReleasePipline(
          argParser: argParser,
          argResults: argResults!,
        );
      case ReleaseTarget.ios:
        throw UnimplementedError();
      // return IosReleasePipeline(argResults: argResults);
      case ReleaseTarget.iosFramework:
        throw UnimplementedError();
      // return IosFrameworkReleasePipeline(argResults: argResults);
      case ReleaseTarget.aar:
        throw UnimplementedError();
      // return AarReleasePipeline(argResults: argResults);
    }
  }
}
