import 'dart:convert';
import 'dart:io';

import 'package:cli_io/cli_io.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/json_output.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../../helpers.dart';
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
          isJsonModeRef.overrideWith(() => false),
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

    test(
      'exits with code 70 when unable to determine Flutter versions',
      () async {
        when(
          () => shorebirdFlutter.getVersionString(),
        ).thenAnswer((_) async => '1.0.0');
        when(
          () => shorebirdFlutter.getVersions(),
        ).thenThrow(Exception('error'));
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(ExitCode.software.code)),
        );
        verifyInOrder([
          () => logger.progress('Fetching Flutter versions'),
          () => shorebirdFlutter.getVersionString(),
          () => shorebirdFlutter.getVersions(),
          () => progress.fail('Failed to fetch Flutter versions.'),
          () => logger.err('Exception: error'),
        ]);
      },
    );

    test(
      'exits with code 0 when able to determine Flutter versions w/out current version',
      () async {
        const versions = ['1.0.0', '1.0.1'];
        when(() => shorebirdFlutter.getVersionString()).thenThrow(
          const ProcessException('flutter', ['--version'], 'Flutter 1.0.0'),
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
      },
    );

    test('exits with code 0 when able to determine Flutter versions '
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

    group('when --json is passed', () {
      late List<String> stdoutOutput;

      R runJsonWithOverrides<R>(R Function() body) {
        return runScoped(
          body,
          values: {
            isJsonModeRef.overrideWith(() => true),
            loggerRef.overrideWith(() => logger),
            shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
          },
        );
      }

      setUp(() {
        stdoutOutput = [];
        command = runJsonWithOverrides(FlutterVersionsListCommand.new);
      });

      test('emits JSON success with versions and current_version', () async {
        const versions = ['1.0.0', '1.0.1'];
        when(
          () => shorebirdFlutter.getVersionString(),
        ).thenAnswer((_) async => '1.0.0');
        when(
          () => shorebirdFlutter.getVersions(),
        ).thenAnswer((_) async => versions);

        final exitCode = await captureStdout(
          () => runJsonWithOverrides(command.run),
          captured: stdoutOutput,
        );

        expect(exitCode, equals(ExitCode.success.code));
        expect(stdoutOutput, isNotEmpty);
        final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
        expect(json['status'], equals('success'));
        final data = json['data'] as Map<String, dynamic>;
        expect(data['current_version'], equals('1.0.0'));
        expect(data['versions'], equals(['1.0.1', '1.0.0']));
        verifyNever(() => logger.info(any()));
      });

      test('emits null current_version when getVersionString throws', () async {
        const versions = ['1.0.0', '1.0.1'];
        when(() => shorebirdFlutter.getVersionString()).thenThrow(
          const ProcessException('flutter', ['--version']),
        );
        when(
          () => shorebirdFlutter.getVersions(),
        ).thenAnswer((_) async => versions);

        final exitCode = await captureStdout(
          () => runJsonWithOverrides(command.run),
          captured: stdoutOutput,
        );

        expect(exitCode, equals(ExitCode.success.code));
        final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>;
        expect(data['current_version'], isNull);
      });

      test('emits JSON error when getVersions fails', () async {
        when(
          () => shorebirdFlutter.getVersionString(),
        ).thenAnswer((_) async => '1.0.0');
        when(
          () => shorebirdFlutter.getVersions(),
        ).thenThrow(Exception('network error'));

        final exitCode = await captureStdout(
          () => runJsonWithOverrides(command.run),
          captured: stdoutOutput,
        );

        expect(exitCode, equals(ExitCode.software.code));
        final json = jsonDecode(stdoutOutput.first) as Map<String, dynamic>;
        expect(json['status'], equals('error'));
        final error = json['error'] as Map<String, dynamic>;
        expect(error['code'], equals('fetch_failed'));
        verifyNever(() => logger.info(any()));
        verifyNever(() => logger.err(any()));
      });

      test('does not create a progress spinner', () async {
        when(
          () => shorebirdFlutter.getVersionString(),
        ).thenAnswer((_) async => '1.0.0');
        when(
          () => shorebirdFlutter.getVersions(),
        ).thenAnswer((_) async => ['1.0.0']);

        await captureStdout(
          () => runJsonWithOverrides(command.run),
          captured: stdoutOutput,
        );

        verifyNever(() => logger.progress(any()));
      });
    });
  });
}
