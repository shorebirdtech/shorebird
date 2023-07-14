import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:shorebird_code_push/shorebird_code_push_io.dart';
import 'package:shorebird_code_push/src/updater.dart';
import 'package:test/test.dart';

class _MockUpdater extends Mock implements Updater {}

void main() {
  group(ShorebirdCodePush, () {
    late List<String> printLogs;
    late Updater updater;
    late ShorebirdCodePush shorebirdCodePush;

    setUp(() {
      printLogs = [];
      updater = _MockUpdater();
      when(() => updater.currentPatchNumber()).thenReturn(0);
      shorebirdCodePush = runZoned(
        () => ShorebirdCodePush.test(updater: updater),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printLogs.add(line),
        ),
      );
    });

    test('can be instantiated', () {
      shorebirdCodePush = runZoned(
        ShorebirdCodePush.new,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printLogs.add(line),
        ),
      );
      expect(shorebirdCodePush, isNotNull);
      expect(
        printLogs,
        [
          startsWith(
            '''[ShorebirdCodePush]: Error initializing updater: Invalid argument(s): Failed to lookup symbol''',
          ),
          equals(
            '''[ShorebirdCodePush]: Shorebird Engine not available, using no-op implementation.\n''',
          ),
        ],
      );
    });

    test('logs error when updater cannot be initialized', () {
      final printLogs = <String>[];
      final exception = Exception('Failed to lookup symbol');
      when(() => updater.currentPatchNumber()).thenThrow(exception);
      runZoned(
        () => ShorebirdCodePush.test(updater: updater),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printLogs.add(line),
        ),
      );
      expect(
        printLogs,
        [
          equals('[ShorebirdCodePush]: Error initializing updater: $exception'),
          equals(
            '''[ShorebirdCodePush]: Shorebird Engine not available, using no-op implementation.\n''',
          ),
        ],
      );
    });

    group('isShorebirdAvailable', () {
      test('proxies to delegate', () {
        expect(shorebirdCodePush.isShorebirdAvailable(), isTrue);
      });
    });

    group('isNewPatchAvailableForDownload', () {
      test('proxies to delegate', () {
        when(() => updater.checkForUpdate()).thenReturn(true);
        expectLater(
          shorebirdCodePush.isNewPatchAvailableForDownload(),
          completion(isTrue),
        );
      });
    });

    group('currentPatchNumber', () {
      test('proxies to delegate', () {
        when(() => updater.currentPatchNumber()).thenReturn(42);
        expectLater(
          shorebirdCodePush.currentPatchNumber(),
          completion(equals(42)),
        );
      });
    });

    group('nextPatchNumber', () {
      test('proxies to delegate', () {
        when(() => updater.nextPatchNumber()).thenReturn(42);
        expectLater(
          shorebirdCodePush.nextPatchNumber(),
          completion(equals(42)),
        );
      });
    });

    group('downloadUpdateIfAvailable', () {
      test('proxies to delegate', () async {
        when(() => updater.downloadUpdate()).thenAnswer((_) async {});
        await expectLater(
          shorebirdCodePush.downloadUpdateIfAvailable(),
          completes,
        );
      });
    });

    group('isNewPatchReadyToInstall', () {
      test('proxies to delegate', () async {
        when(() => updater.currentPatchNumber()).thenReturn(0);
        when(() => updater.nextPatchNumber()).thenReturn(1);
        await expectLater(
          shorebirdCodePush.isNewPatchReadyToInstall(),
          completion(isTrue),
        );
      });
    });
  });
}
