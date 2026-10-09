import 'dart:io';

import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/cache.dart';
import 'package:shorebird_cli/src/commands/commands.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:test/test.dart';

import '../../mocks.dart';

void main() {
  group('cache clean', () {
    late Cache cache;
    late ShorebirdLogger logger;
    late TestNativePlatform platform;
    late Progress progress;
    late ShorebirdEnv shorebirdEnv;
    late ShorebirdFlutter shorebirdFlutter;
    late ArgResults argResults;
    late CleanCacheCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          cacheRef.overrideWith(() => cache),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          shorebirdEnvRef.overrideWith(() => shorebirdEnv),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    setUp(() {
      cache = MockCache();
      logger = MockShorebirdLogger();
      platform = TestNativePlatform(operatingSystem: NativePlatform.linux);
      progress = MockProgress();
      shorebirdEnv = MockShorebirdEnv();
      shorebirdFlutter = MockShorebirdFlutter();
      argResults = MockArgResults();
      command = runWithOverrides(CleanCacheCommand.new)
        ..testArgResults = argResults;

      when(() => argResults[CleanCacheCommand.unusedFlag]).thenReturn(false);

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

    group('with --unused', () {
      setUp(() {
        when(() => argResults[CleanCacheCommand.unusedFlag]).thenReturn(true);
        when(() => shorebirdFlutter.pruneUnusedRevisions()).thenReturn([]);
        when(() => cache.pruneUnusedArtifacts()).thenReturn([]);
        when(() => cache.pruneUnusedPreviews()).thenReturn([]);
      });

      test('removes only unused cached files', () async {
        when(
          () => shorebirdFlutter.pruneUnusedRevisions(),
        ).thenReturn(['a', 'b']);
        when(() => cache.pruneUnusedArtifacts()).thenReturn(['c']);
        when(() => cache.pruneUnusedPreviews()).thenReturn(['d', 'e', 'f']);

        final result = await runWithOverrides(command.run);

        expect(result, equals(ExitCode.success.code));
        verify(
          () => progress.complete(
            'Removed 2 unused Flutter versions, 1 unused engine artifact, '
            '3 unused previews',
          ),
        ).called(1);
        verifyNever(cache.clear);
      });

      test('lists only what it removed', () async {
        when(() => cache.pruneUnusedPreviews()).thenReturn(['a']);

        await runWithOverrides(command.run);

        verify(
          () => progress.complete('Removed 1 unused preview'),
        ).called(1);
      });

      test('says when there was nothing to remove', () async {
        await runWithOverrides(command.run);

        verify(
          () => progress.complete('Nothing unused to remove'),
        ).called(1);
      });
    });

    group('on failure', () {
      group('on Windows', () {
        setUp(() {
          platform = platform.copyWith(operatingSystem: NativePlatform.windows);
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
          platform = platform.copyWith(operatingSystem: NativePlatform.linux);
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
