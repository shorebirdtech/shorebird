import 'package:shorebird_cli/src/common_arguments.dart';
import 'package:test/test.dart';
import 'helpers.dart';

void main() {
  useTempWorkingDirectory();
  group(CommonArguments, () {
    group('nameError', () {
      String? nameError(String value) => CommonArguments.nameError(
        label: 'Channel name',
        value: value,
        maxLength: 5,
      );

      test('accepts a name within the limit', () {
        expect(nameError('beta'), isNull);
        expect(nameError('a' * 5), isNull);
      });

      test('rejects an empty name', () {
        expect(nameError(''), equals('Channel name must not be blank.'));
      });

      test('rejects a whitespace-only name', () {
        expect(nameError('   '), equals('Channel name must not be blank.'));
      });

      test('rejects a name over the limit', () {
        expect(
          nameError('a' * 6),
          equals('Channel name must be at most 5 characters (got 6).'),
        );
      });
    });
  });
}
