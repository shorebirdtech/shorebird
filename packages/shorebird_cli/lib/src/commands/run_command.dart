import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shorebird_cli/src/args.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/doctor.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/process.dart';
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
        ArgsKey.deviceId,
        abbr: 'd',
        help: 'Target device id or name.',
      )
      ..addOption(
        ArgsKey.target,
        abbr: 't',
        help: 'The main entrypoint file of the application.',
      )
      ..addMultiOption(
        ArgsKey.dartDefine,
        help: 'Additional key-value pairs that will be available as constants '
            '''from the String.fromEnvironment, bool.fromEnvironment, and int.fromEnvironment '''
            'constructors.\n'
            '''Multiple defines can be passed by repeating "--${ArgsKey.dartDefine}" multiple times.''',
        splitCommas: false,
        valueHelp: 'foo=bar',
      )
      ..addOption(
        ArgsKey.flavor,
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

    final deviceId = results[ArgsKey.deviceId] as String?;
    final flavor = results[ArgsKey.flavor] as String?;
    final target = results[ArgsKey.target] as String?;
    final dartDefines = results[ArgsKey.dartDefine] as List<String>?;
    final flutter = await process.start(
      'flutter',
      [
        'run',
        // Eventually we should support running in both debug and release mode.
        '--${ArgsKey.release}',
        if (deviceId != null) '--${ArgsKey.deviceId}=$deviceId',
        if (flavor != null) '--${ArgsKey.flavor}=$flavor',
        if (target != null) '--${ArgsKey.target}=$target',
        if (dartDefines != null)
          ...dartDefines.map((e) => '--${ArgsKey.dartDefine}=$e'),
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
