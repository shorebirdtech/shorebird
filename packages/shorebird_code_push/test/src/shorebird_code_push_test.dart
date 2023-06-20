// ignore_for_file: prefer_const_constructors

import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

class _MockUpdater extends Mock implements Updater {}

void main() {
  group('ShorebirdCodePush', () {
    late Updater updater;
    late ShorebirdCodePush shorebirdCodePush;

    setUp(() {
      updater = _MockUpdater();
      shorebirdCodePush = ShorebirdCodePush(
        createUpdater: () => updater,
      );
    });

    group('checkForUpdate', () {
      test('returns false if no update is available', () async {
        when(() => updater.checkForUpdate()).thenAnswer((_) => false);
        expect(await shorebirdCodePush.checkForUpdate(), isFalse);
      });

      test('returns true if an update is available', () async {
        when(() => updater.checkForUpdate()).thenAnswer((_) => true);
        expect(await shorebirdCodePush.checkForUpdate(), true);
      });
    });

    group('currentPatchNumber', () {
      test('forwards the return value of updater.currentPatchNumber', () async {
        when(() => updater.currentPatchNumber()).thenReturn(1);
        expect(await shorebirdCodePush.currentPatchVersion(), 1);

        when(() => updater.currentPatchNumber()).thenReturn(null);
        expect(await shorebirdCodePush.currentPatchVersion(), null);
      });
    });
  });
}
