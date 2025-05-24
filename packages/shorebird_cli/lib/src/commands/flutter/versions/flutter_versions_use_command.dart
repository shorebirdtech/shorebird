import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';

/// {@template flutter_versions_use_command}
/// `shorebird flutter versions use`
/// Set the global Flutter version used by Shorebird.
/// {@endtemplate}
class FlutterVersionsUseCommand extends ShorebirdCommand {
  /// {@macro flutter_versions_use_command}
  FlutterVersionsUseCommand();

  @override
  String get description => 'Set the global Flutter version used by Shorebird.';

  @override
  String get name => 'use';

  @override
  String get invocation => 'shorebird flutter versions use <version>';

  @override
  Future<int> run() async {
    final args = results.rest;
    if (args.isEmpty) {
      logger
        ..err('Please specify a Flutter version.')
        ..info('Usage: $invocation')
        ..info('')
        ..info('Available versions can be listed with:')
        ..info('  shorebird flutter versions list');
      return ExitCode.usage.code;
    }

    final requestedVersion = args.first;

    // Проверяем, является ли это версией или git revision
    final progress = logger.progress('Resolving Flutter version');

    final String? revision;
    try {
      revision = await shorebirdFlutter.resolveFlutterRevision(
        requestedVersion,
      );
    } on Exception catch (e) {
      progress.fail('Failed to resolve Flutter version');
      logger.err('$e');
      return ExitCode.software.code;
    }

    if (revision == null) {
      progress.fail('Version $requestedVersion not found');
      logger
        ..info('')
        ..info('Available versions can be listed with:')
        ..info('  shorebird flutter versions list');
      return ExitCode.software.code;
    }

    progress.complete();

    // Получаем человекочитаемую версию для отображения
    final version = await shorebirdFlutter.getVersionForRevision(
      flutterRevision: revision,
    );
    final displayVersion = version ?? requestedVersion;

    // Проверяем текущую версию
    String? currentVersion;
    try {
      currentVersion = await shorebirdFlutter.getVersionString();
    } on Exception {
      // Игнорируем ошибки при получении текущей версии
    }

    if (currentVersion == version && version != null) {
      logger.info('Flutter $displayVersion is already the active version.');
      return ExitCode.success.code;
    }

    // Устанавливаем Flutter если его еще нет
    final installProgress = logger.progress(
      'Setting Flutter version to $displayVersion',
    );

    try {
      // Устанавливаем версию если ее еще нет
      await shorebirdFlutter.installRevision(revision: revision);

      // Обновляем файл flutter.version
      final versionFile = File(
        p.join(
          shorebirdEnv.shorebirdRoot.path,
          'bin',
          'internal',
          'flutter.version',
        ),
      );

      if (!versionFile.existsSync()) {
        versionFile.createSync(recursive: true);
      }

      versionFile.writeAsStringSync(revision);

      installProgress.complete();

      logger
        ..info('')
        ..success('Flutter version set to $displayVersion')
        ..info('')
        ..info('To verify the change, run:')
        ..info('  ${lightCyan.wrap('shorebird flutter --version')}');

      return ExitCode.success.code;
    } on Exception catch (error) {
      installProgress.fail('Failed to set Flutter version');
      logger.err('$error');
      return ExitCode.software.code;
    }
  }
}
