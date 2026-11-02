import 'package:mocktail/mocktail.dart';
import 'package:platform/testing.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/server_notices.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(ServerNotices, () {
    late ShorebirdLogger logger;
    late TestNativePlatform platform;
    late ServerNotices notices;

    setUp(() {
      logger = MockShorebirdLogger();
      platform = TestNativePlatform(environment: {});
      notices = ServerNotices();
    });

    void printAll() => runScoped(
      notices.printAll,
      values: {
        loggerRef.overrideWith(() => logger),
        platformRef.overrideWith(() => platform),
      },
    );

    test('prints each notice once, as a warning', () {
      notices
        ..add('Patches are paused.')
        ..add('Patches are paused.')
        ..add('Another notice.');
      printAll();
      verifyInOrder([
        () => logger.warn('Patches are paused.'),
        () => logger.warn('Another notice.'),
      ]);
      verifyNoMoreInteractions(logger);
    });

    test('forgets what it printed', () {
      notices.add('Patches are paused.');
      printAll();
      printAll();
      verify(() => logger.warn('Patches are paused.')).called(1);
    });

    test('prints nothing when there is nothing', () {
      printAll();
      verifyNever(() => logger.warn(any()));
    });

    group('on GitHub Actions', () {
      setUp(() {
        platform = TestNativePlatform(environment: {'GITHUB_ACTIONS': 'true'});
      });

      test('prints each notice once, as a warning annotation', () {
        notices
          ..add('Patches are paused.')
          ..add('Patches are paused.')
          ..add('Another notice.');
        printAll();
        verifyInOrder([
          () => logger.info('::warning title=Shorebird::Patches are paused.'),
          () => logger.info('::warning title=Shorebird::Another notice.'),
        ]);
        verifyNoMoreInteractions(logger);
      });

      test('escapes percent signs and line breaks', () {
        notices.add('86% used.\r\nRaise the limit.');
        printAll();
        verify(
          () => logger.info(
            '::warning title=Shorebird::86%25 used.%0D%0ARaise the limit.',
          ),
        ).called(1);
      });
    });
  });
}
