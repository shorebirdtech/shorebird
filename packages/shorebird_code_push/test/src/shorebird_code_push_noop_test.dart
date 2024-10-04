// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:shorebird_code_push/src/shorebird_code_push_noop.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdCodePushNoop, () {
    late List<String> printLogs;
    late ShorebirdCodePushNoop shorebirdCodePush;

    setUp(() {
      printLogs = [];
      shorebirdCodePush = runZoned(
        ShorebirdCodePushNoop.new,
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printLogs.add(line),
        ),
      );
    });

    test('logs warning when instantiated', () {
      const expected = '''
[ShorebirdCodePush]: Shorebird Engine not available, using no-op implementation.
This occurs when using package:shorebird_code_push in an app that does not
contain the Shorebird Engine. Most commonly this is due to building with
`flutter build` or `flutter run` instead of `shorebird release`.\n''';
      expect(printLogs, equals([expected]));
    });

    group('isShorebirdAvailable', () {
      test('returns false', () {
        expect(shorebirdCodePush.isShorebirdAvailable(), isFalse);
      });
    });

    group('isNewPatchAvailableForDownload', () {
      test('returns false', () {
        expectLater(
          shorebirdCodePush.isNewPatchAvailableForDownload(),
          completion(isFalse),
        );
      });
    });

    group('currentPatchNumber', () {
      test('returns null', () {
        expectLater(shorebirdCodePush.currentPatchNumber(), completion(isNull));
      });
    });

    group('nextPatchNumber', () {
      test('returns null', () {
        expectLater(shorebirdCodePush.nextPatchNumber(), completion(isNull));
      });
    });

    group('downloadUpdate', () {
      test('completes', () {
        expectLater(shorebirdCodePush.downloadUpdateIfAvailable(), completes);
      });
    });

    group('isNewPatchReadyToInstall', () {
      test('returns false', () {
        expectLater(
          shorebirdCodePush.isNewPatchReadyToInstall(),
          completion(isFalse),
        );
      });
    });
  });
}
