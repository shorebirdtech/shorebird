// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('UniqueUsersBreakdownEntry', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = UniqueUsersBreakdownEntry(
        groupBy: 'example',
        groupValue: 'example',
        uniqueUsers: 0,
      );
      final parsed = UniqueUsersBreakdownEntry.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(UniqueUsersBreakdownEntry.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => UniqueUsersBreakdownEntry.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
