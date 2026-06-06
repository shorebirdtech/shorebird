// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetUniqueUsersResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetUniqueUsersResponse(
        uniqueUsers: 0,
        granularity: 'example',
        range: UniqueUsersRange(
          start: DateTime.utc(2024),
          end: DateTime.utc(2024),
        ),
        asOf: DateTime.utc(2024),
      );
      final parsed = GetUniqueUsersResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetUniqueUsersResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetUniqueUsersResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
