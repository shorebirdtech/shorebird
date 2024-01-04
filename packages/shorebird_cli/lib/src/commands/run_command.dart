import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:shorebird_cli/src/shorebird_validator.dart';

/// {@template run_command}
/// `shorebird run`
/// Run the Flutter application.
/// {@endtemplate}
class RunCommand extends ShorebirdCommand {
  /// {@macro run_command}
  RunCommand() {
    argParser
      ..addOption(
        'device-id',
        abbr: 'd',
        help: 'Target device id or name.',
      )
      ..addOption(
        'target',
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addMultiOption(
        'dart-define',
        help: 'Additional key-value pairs that will be available as constants '
            '''from the String.fromEnvironment, bool.fromEnvironment, and int.fromEnvironment '''
            'constructors.\n'
            '''Multiple defines can be passed by repeating "--dart-define" multiple times.''',
        splitCommas: false,
        valueHelp: 'foo=bar',
      )
      ..addOption(
        'flavor',
        help: 'The product flavor to use when building the app.',
      );
  }

  @override
  String get description => 'Run the Flutter application.';

  @override
  String get name => 'run';

  @override
  bool get hidden => true;

  @override
  Future<int> run() async {
    logger.warn(
      '''
This command is deprecated and will be removed in a future release.
Please use "shorebird preview" instead.''',
    );

    // TODO(bryanoltman): check run target and run either
    // doctor.iosValidators or doctor.androidValidators as appropriate.
    try {
      await shorebirdValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        validators: doctor.allValidators,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    logger.info('Running app...');

    final deviceId = results['device-id'] as String?;
    final flavor = results['flavor'] as String?;
    final target = results['target'] as String?;
    final dartDefines = results['dart-define'] as List<String>?;
    final flutter = await process.start(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--release',
        if (deviceId != null) '--device-id=$deviceId',
        if (flavor != null) '--flavor=$flavor',
        if (target != null) '--target=$target',
        if (dartDefines != null) ...dartDefines.map((e) => '--dart-define=$e'),
        ...results.rest,
      ],
      runInShell: true,
    );

    flutter.stdout.listen((event) {
      logger.info(utf8.decode(event));
    });
    flutter.stderr.listen((event) {
      logger.err(utf8.decode(event));
    });

    unawaited(flutter.stdin.addStream(stdin));

    return flutter.exitCode;
  }
}
