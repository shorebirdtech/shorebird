import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logger.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

class _MockCache extends Mock implements Cache {}

class _MockLogger extends Mock implements Logger {}

class _MockPlatform extends Mock implements Platform {}

class _MockProgress extends Mock implements Progress {}

class _MockShorebirdEnv extends Mock implements ShorebirdEnv {}

void main() {
  group('cache clean', () {
    late Cache cache;
    late Logger logger;
    late Platform platform;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late CleanCacheCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
        },
      );
    }

    setUp(() {
      cache = _MockCache();
      logger = _MockLogger();
      platform = _MockPlatform();
      progress = _MockProgress();
      shorebirdEnv = _MockShorebirdEnv();
      command = runWithOverrides(CleanCacheCommand.new);

      when(() => logger.progress(any())).thenReturn(progress);
      when(() => shorebirdEnv.shorebirdRoot).thenReturn(
        Directory.systemTemp.createTempSync(),
      );
    });

    test('has a description', () {
      expect(command.description, isNotEmpty);
    });

    test('clears the cache', () async {
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => progress.complete('Cleared cache')).called(1);
      verify(cache.clear).called(1);
    });

    group('on failure', () {
      group('on Windows', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(true);
        });

        test('tells the user how to find the issue and exits with code 70',
            () async {
          when(() => cache.clear()).thenThrow(
            const FileSystemException('Failed to delete'),
          );

          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.software.code));
          verify(() => progress.fail(any())).called(1);
          verify(() => logger.info(any())).called(1);
        });
      });

      group('on a non-Windows OS', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(false);
        });

        test('prints error message and exits with code 70', () async {
          when(() => cache.clear()).thenThrow(
            const FileSystemException('Failed to delete'),
          );

          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.software.code));
          verify(() => progress.fail(any())).called(1);
          verifyNever(() => logger.info(any()));
        });
      });
    });
  });
}
