import 'package:mason_logger/mason_logger.dart';
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

  group('notesSummary', () {
    test('shows a single line as is', () {
      expect(
        notesSummary('Fixes the login crash'),
        equals(
          '📝 Notes (private): ${lightCyan.wrap('Fixes the login crash')}',
        ),
      );
    });

    test('shows the first line of Windows line endings', () {
      expect(
        notesSummary('Fixes the login crash\r\nAlso the timeout'),
        equals(
          '📝 Notes (private): ${lightCyan.wrap('Fixes the login crash')} …',
        ),
      );
    });
  });
}
