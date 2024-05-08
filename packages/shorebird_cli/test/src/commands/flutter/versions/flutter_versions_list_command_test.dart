import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../../mocks.dart';

void main() {
  group(FlutterVersionsListCommand, () {
    late Progress progress;
    late ShorebirdLogger logger;
    late ShorebirdFlutter shorebirdFlutter;
    late FlutterVersionsListCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          loggerRef.overrideWith(() => logger),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      progress = MockProgress();
      logger = MockShorebirdLogger();
      shorebirdFlutter = MockShorebirdFlutter();
      command = runWithOverrides(FlutterVersionsListCommand.new);

      when(() => logger.progress(any())).thenReturn(progress);
    });

    test('has correct name and description', () {
      expect(command.name, equals('list'));
      expect(command.description, equals('List available Flutter versions.'));
    });

    test('exits with code 70 when unable to determine Flutter versions',
        () async {
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => '1.0.0');
      when(() => shorebirdFlutter.getVersions()).thenThrow('error');
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.software.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => shorebirdFlutter.getVersionString(),
        () => shorebirdFlutter.getVersions(),
        () => progress.fail('Failed to fetch Flutter versions.'),
        () => logger.err('error'),
      ]);
    });

    test(
        'exits with code 0 when able to determine Flutter versions w/out current version',
        () async {
      const versions = ['1.0.0', '1.0.1'];
      when(() => shorebirdFlutter.getVersionString()).thenThrow(
        const ProcessException(
          'flutter',
          ['--version'],
          'Flutter 1.0.0',
        ),
      );
      when(
        () => shorebirdFlutter.getVersions(),
      ).thenAnswer((_) async => versions);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => shorebirdFlutter.getVersionString(),
        () => shorebirdFlutter.getVersions(),
        () => progress.cancel(),
        () => logger.info('📦 Flutter Versions'),
        () => logger.info('  1.0.1'),
        () => logger.info('  1.0.0'),
      ]);
    });

    test(
        'exits with code 0 when able to determine Flutter versions '
        'as well as the current version', () async {
      const versions = ['1.0.0', '1.0.1'];
      when(
        () => shorebirdFlutter.getVersionString(),
      ).thenAnswer((_) async => versions.first);

      when(
        () => shorebirdFlutter.getVersions(),
      ).thenAnswer((_) async => versions);
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );
      verifyInOrder([
        () => logger.progress('Fetching Flutter versions'),
        () => shorebirdFlutter.getVersionString(),
        () => shorebirdFlutter.getVersions(),
        () => progress.cancel(),
        () => logger.info('📦 Flutter Versions'),
        () => logger.info('  1.0.1'),
        () => logger.info(lightCyan.wrap('✓ 1.0.0')),
      ]);
    });
  });
}
