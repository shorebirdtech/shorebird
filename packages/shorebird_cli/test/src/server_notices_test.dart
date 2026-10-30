import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/server_notices.dart';
import 'package:test/test.dart';

import 'helpers.dart';
import 'mocks.dart';

void main() {
  useTempWorkingDirectory();

  group(ServerNotices, () {
    late ShorebirdLogger logger;
    late ServerNotices notices;

    setUp(() {
      logger = MockShorebirdLogger();
      notices = ServerNotices();
    });

    void printAll() => runScoped(
      notices.printAll,
      values: {loggerRef.overrideWith(() => logger)},
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
  });
}
