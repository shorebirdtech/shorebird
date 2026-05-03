import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group('cache clean', () {
    late Cache cache;
    late ShorebirdLogger logger;
    late Platform platform;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late CleanCacheCommand command;

    setUpAll(() {
      // Required for `any()` to work with `cache.updateAll(...)` in
      // `verifyNever` calls.
      registerFallbackValue(Duration.zero);
    });

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
      cache = MockCache();
      logger = MockShorebirdLogger();
      platform = MockPlatform();
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      command = runWithOverrides(CleanCacheCommand.new);

      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => shorebirdEnv.shorebirdRoot,
      ).thenReturn(Directory.systemTemp.createTempSync());
    });

    test('has a non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    test('clears the cache', () async {
      when(cache.clear).thenAnswer((_) async {});
      final result = await runWithOverrides(command.run);
      expect(result, equals(ExitCode.success.code));
      verify(() => progress.complete('Cleared cache')).called(1);
      verify(cache.clear).called(1);
    });

    // Regression guard for https://github.com/shorebirdtech/shorebird/issues/2234
    // (and the unit-test follow-up tracked in #2273). The earlier flow could
    // end up populating the cache before clearing it, defeating the point of
    // `cache clean`. Even though the current implementation only calls
    // `clear()`, this assertion makes sure `updateAll` doesn't sneak back in.
    test('does not update the cache before clearing it', () async {
      when(cache.clear).thenAnswer((_) async {});
      await runWithOverrides(command.run);
      verifyNever(() => cache.updateAll(any()));
    });

    group('on failure', () {
      group('on Windows', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(true);
        });

        test(
          'tells the user how to find the issue and exits with code 70',
          () async {
            when(
              () => cache.clear(),
            ).thenThrow(const FileSystemException('Failed to delete'));

            final result = await runWithOverrides(command.run);

            expect(result, equals(ExitCode.software.code));
            verify(() => progress.fail(any())).called(1);
            verify(
              () => logger.info(
                any(
                  that: stringContainsInOrder([
                    '''This could be because a program is using a file in the cache directory. To find and stop such a program, see''',
                    'https://superuser.com/questions/1333118/cant-delete-empty-folder-because-it-is-used',
                  ]),
                ),
              ),
            ).called(1);
          },
        );
      });

      group('on a non-Windows OS', () {
        setUp(() {
          when(() => platform.isWindows).thenReturn(false);
        });

        test('prints error message and exits with code 70', () async {
          when(
            () => cache.clear(),
          ).thenThrow(const FileSystemException('Failed to delete'));

          final result = await runWithOverrides(command.run);

          expect(result, equals(ExitCode.software.code));
          verify(() => progress.fail(any())).called(1);
          verifyNever(() => logger.info(any()));
        });
      });
    });
  });
}
