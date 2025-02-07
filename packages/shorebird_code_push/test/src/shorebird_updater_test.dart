import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:test/test.dart';

import '../override_print.dart';

void main() {
  group(ShorebirdUpdater, () {
    test(
      'can be instantiated',
      overridePrint((_) {
        expect(ShorebirdUpdater.new, returnsNormally);
      }),
    );

    group(UpdateException, () {
      test('overrides toString', () {
        const message = 'message';
        const reason = UpdateFailureReason.downloadFailed;
        const exception = UpdateException(message: message, reason: reason);
        expect(
          exception.toString(),
          equals(
            '[ShorebirdUpdater] UpdateException: $message (${reason.name})',
          ),
        );
      });
    });

    group(ReadPatchException, () {
      test('overrides toString', () {
        const message = 'message';
        const exception = ReadPatchException(message: message);
        expect(
          exception.toString(),
          equals('[ShorebirdUpdater] ReadPatchException: $message'),
        );
      });
    });
  });
}
