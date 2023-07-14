import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push/src/shorebird_code_push_ffi.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

class _MockUpdater extends Mock implements Updater {}

void main() {
  group(ShorebirdCodePushFfi, () {
    late Updater updater;
    late ShorebirdCodePushFfi shorebirdCodePush;

    setUp(() {
      updater = _MockUpdater();
      shorebirdCodePush = ShorebirdCodePushFfi(updater: updater);
    });

    group('isShorebirdAvailable', () {
      test('returns true', () {
        expect(shorebirdCodePush.isShorebirdAvailable(), isTrue);
      });
    });

    group('isNewPatchAvailableForDownload', () {
      test('returns false if no update is available', () async {
        when(() => updater.checkForUpdate()).thenAnswer((_) => false);
        await expectLater(
          shorebirdCodePush.isNewPatchAvailableForDownload(),
          completion(isFalse),
        );
      });

      test('returns true if an update is available', () async {
        when(() => updater.checkForUpdate()).thenAnswer((_) => true);
        await expectLater(
          shorebirdCodePush.isNewPatchAvailableForDownload(),
          completion(isTrue),
        );
      });

      test('surfaces exception if updater throws exception', () async {
        when(() => updater.checkForUpdate()).thenThrow(Exception('oh no'));
        await expectLater(
          () => shorebirdCodePush.isNewPatchAvailableForDownload(),
          throwsException,
        );
      });
    });

    group('currentPatchNumber', () {
      test('returns null if current patch is reported as 0', () async {
        when(() => updater.currentPatchNumber()).thenReturn(0);
        await expectLater(
          shorebirdCodePush.currentPatchNumber(),
          completion(isNull),
        );
      });

      test('forwards the return value of updater.currentPatchNumber', () async {
        when(() => updater.currentPatchNumber()).thenReturn(1);
        await expectLater(
          shorebirdCodePush.currentPatchNumber(),
          completion(equals(1)),
        );
      });

      test('surfaces exception if updater throws exception', () async {
        when(() => updater.currentPatchNumber()).thenThrow(Exception('oh no'));
        await expectLater(
          () => shorebirdCodePush.currentPatchNumber(),
          throwsException,
        );
      });
    });

    group('nextPatchNumber', () {
      test('returns null if current patch is reported as 0', () async {
        when(() => updater.nextPatchNumber()).thenReturn(0);
        await expectLater(
          shorebirdCodePush.nextPatchNumber(),
          completion(isNull),
        );
      });

      test('forwards the return value of updater.nextPatchNumber', () async {
        when(() => updater.nextPatchNumber()).thenReturn(1);
        await expectLater(
          shorebirdCodePush.nextPatchNumber(),
          completion(equals(1)),
        );
      });

      test('surfaces exception if updater throws exception', () async {
        when(() => updater.nextPatchNumber()).thenThrow(Exception('oh no'));
        await expectLater(
          () => shorebirdCodePush.nextPatchNumber(),
          throwsException,
        );
      });
    });

    group('downloadUpdate', () {
      test('completes', () async {
        when(() => updater.downloadUpdate()).thenReturn(null);
        await expectLater(
          shorebirdCodePush.downloadUpdateIfAvailable(),
          completes,
        );
      });

      test('surfaces exception if updater throws exception', () async {
        when(() => updater.downloadUpdate()).thenThrow(Exception('oh no'));
        await expectLater(
          () => shorebirdCodePush.downloadUpdateIfAvailable(),
          throwsException,
        );
      });
    });

    group('isNewPatchReadyToInstall', () {
      test('returns false if no new patch is available', () async {
        when(() => updater.currentPatchNumber()).thenReturn(1);
        when(() => updater.nextPatchNumber()).thenReturn(0);
        await expectLater(
          shorebirdCodePush.isNewPatchReadyToInstall(),
          completion(isFalse),
        );
      });

      test(
        'returns false if the next patch is the same as the current patch',
        () async {
          when(() => updater.currentPatchNumber()).thenReturn(1);
          when(() => updater.nextPatchNumber()).thenReturn(1);
          await expectLater(
            shorebirdCodePush.isNewPatchReadyToInstall(),
            completion(isFalse),
          );
        },
      );

      test(
          'returns true if the next patch number is greater '
          'than the current patch number', () async {
        when(() => updater.currentPatchNumber()).thenReturn(1);
        when(() => updater.nextPatchNumber()).thenReturn(2);
        await expectLater(
          shorebirdCodePush.isNewPatchReadyToInstall(),
          completion(isTrue),
        );
      });
    });
  });
}
