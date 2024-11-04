import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push/src/shorebird_updater.dart';
import 'package:shorebird_code_push/src/shorebird_updater_web.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

import '../override_print.dart';

class _MockUpdater extends Mock implements Updater {}

void main() {
  group(ShorebirdUpdaterImpl, () {
    late Updater updater;
    late ShorebirdUpdaterImpl shorebirdUpdater;

    setUp(() {
      updater = _MockUpdater();
    });

    test(
      'logs unavailable error',
      overridePrint((logs) {
        shorebirdUpdater = ShorebirdUpdaterImpl(updater);
        expect(
          logs,
          contains(
            isA<String>().having(
              (s) => s,
              'message',
              contains(
                '''The Shorebird Updater is unavailable in the current environment.''',
              ),
            ),
          ),
        );
      }),
    );

    group('isAvailable', () {
      test(
        'returns false',
        overridePrint((_) {
          shorebirdUpdater = ShorebirdUpdaterImpl(updater);
          expect(shorebirdUpdater.isAvailable, isFalse);
        }),
      );
    });

    group('readPatch', () {
      test(
        'returns null',
        overridePrint((_) async {
          await expectLater(
            shorebirdUpdater.readCurrentPatch(),
            completion(isNull),
          );
          await expectLater(
            shorebirdUpdater.readNextPatch(),
            completion(isNull),
          );
        }),
      );
    });

    group('checkForUpdate', () {
      test(
        'returns UpdateStatus.unavailable',
        overridePrint((_) async {
          await expectLater(
            shorebirdUpdater.checkForUpdate(),
            completion(equals(UpdateStatus.unavailable)),
          );
        }),
      );
    });

    group('update', () {
      test(
        'does nothing',
        overridePrint((_) async {
          await expectLater(shorebirdUpdater.update(), completes);
          verifyNever(updater.downloadUpdate);
        }),
      );
    });
  });
}
