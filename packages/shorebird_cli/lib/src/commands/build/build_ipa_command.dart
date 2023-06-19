import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_build_mixin.dart';
import 'package:shorebird_cli/src/shorebird_config_mixin.dart';
import 'package:shorebird_cli/src/shorebird_validation_mixin.dart';

/// {@template build_ipa_command}
/// `shorebird build ipa`
/// Builds an .xcarchive and optionally .ipa for an iOS app to be generated for
/// App Store submission.
/// {@endtemplate}
class BuildIpaCommand extends ShorebirdCommand
    with ShorebirdConfigMixin, ShorebirdValidationMixin, ShorebirdBuildMixin {
  /// {@macro build_ipa_command}
  BuildIpaCommand({super.validators}) {
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
        'codesign',
        help:
            '''Codesign the application bundle (only available on device builds).''',
      );
  }

  @override
  String get description =>
      '''Builds an .xcarchive and optionally .ipa for an iOS app to be generated for App Store submission.''';

  @override
  String get name => 'ipa';

  @override
  Future<int> run() async {
    try {
      await validatePreconditions(
        checkUserIsAuthenticated: true,
        checkValidators: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final codesign = results['codesign'] as bool;

    if (!codesign) {
      logger.warn('''
Codesigning is disabled. You must manually codesign before deploying to devices.''');
    }

    final buildProgress = logger.progress('Building ipa');
    try {
      await buildIpa(
        flavor: flavor,
        target: target,
        codesign: codesign,
      );
    } on ProcessException catch (error) {
      buildProgress.fail('Failed to build: ${error.message}');
      return ExitCode.software.code;
    }

    buildProgress.complete();

    final xcarchivePath = p.join('build', 'ios', 'archive', 'Runner.xcarchive');

    logger.info('''
📦 Generated an xcode archive at:
${lightCyan.wrap(xcarchivePath)}''');

    if (!codesign) {
      logger.info(
        'Codesigning disabled via "--no-codesign". Skipping ipa generation.',
      );
      return ExitCode.success.code;
    }

    final ipaPath = p.join('build', 'ios', 'ipa', 'Runner.ipa');

    logger.info('''
📦 Generated an ipa at:
${lightCyan.wrap(ipaPath)}''');

    return ExitCode.success.code;
  }
}
