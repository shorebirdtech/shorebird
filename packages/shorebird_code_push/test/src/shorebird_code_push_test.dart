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
    Object? loggedError;

    setUp(() {
      loggedError = null;
      updater = _MockUpdater();
      shorebirdCodePush = ShorebirdCodePush.forTest(
        logError: ([object]) => loggedError = object,
        buildUpdater: () => updater,
      );
    });

    group('checkForUpdate', () {
      test('returns false if no update is available', () async {
        when(() => updater.checkForUpdate()).thenAnswer((_) => false);
        expect(await shorebirdCodePush.checkForUpdate(), isFalse);
        expect(loggedError, isNull);
      });

      test('returns true if an update is available', () async {
        when(() => updater.checkForUpdate()).thenAnswer((_) => true);
        expect(await shorebirdCodePush.checkForUpdate(), true);
        expect(loggedError, isNull);
      });

      test('returns false if updater throws exception', () async {
        when(() => updater.checkForUpdate()).thenThrow(Exception('oh no'));
        expect(await shorebirdCodePush.checkForUpdate(), isFalse);
        expect(loggedError, '[ShorebirdCodePush] Exception: oh no');
      });
    });

    group('currentPatchNumber', () {
      test('returns null if current patch is reported as 0', () async {
        when(() => updater.currentPatchNumber()).thenReturn(0);
        expect(await shorebirdCodePush.currentPatchNumber(), isNull);
        expect(loggedError, isNull);
      });

      test('forwards the return value of updater.currentPatchNumber', () async {
        when(() => updater.currentPatchNumber()).thenReturn(1);
        expect(await shorebirdCodePush.currentPatchNumber(), 1);
        expect(loggedError, isNull);
      });

      test('returns null if updater throws exception', () async {
        when(() => updater.currentPatchNumber()).thenThrow(Exception('oh no'));
        expect(await shorebirdCodePush.currentPatchNumber(), isNull);
        expect(loggedError, '[ShorebirdCodePush] Exception: oh no');
      });
    });

    group('nextPatchNumber', () {
      test('returns null if current patch is reported as 0', () async {
        when(() => updater.nextPatchNumber()).thenReturn(0);
        expect(await shorebirdCodePush.nextPatchNumber(), isNull);
        expect(loggedError, isNull);
      });

      test('forwards the return value of updater.nextPatchNumber', () async {
        when(() => updater.nextPatchNumber()).thenReturn(1);
        expect(await shorebirdCodePush.nextPatchNumber(), 1);
        expect(loggedError, isNull);
      });

      test('returns null if updater throws exception', () async {
        when(() => updater.nextPatchNumber()).thenThrow(Exception('oh no'));
        expect(await shorebirdCodePush.nextPatchNumber(), isNull);
        expect(loggedError, '[ShorebirdCodePush] Exception: oh no');
      });
    });

    group('downloadUpdate', () {
      test('forwards the return value of updater.nextPatchNumber', () async {
        when(() => updater.downloadUpdate()).thenReturn(null);
        await expectLater(shorebirdCodePush.downloadUpdate(), completes);
        expect(loggedError, isNull);
      });

      test('logs error if updater throws exception', () async {
        when(() => updater.downloadUpdate()).thenThrow(Exception('oh no'));
        await expectLater(shorebirdCodePush.downloadUpdate(), completes);
        expect(loggedError, '[ShorebirdCodePush] Exception: oh no');
      });
    });
  });
}
