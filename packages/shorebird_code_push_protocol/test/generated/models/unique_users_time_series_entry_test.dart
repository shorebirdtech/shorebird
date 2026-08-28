// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('UniqueUsersTimeSeriesEntry', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = UniqueUsersTimeSeriesEntry(
        period: DateTime.utc(2024),
        uniqueUsers: 0,
      );
      final parsed = UniqueUsersTimeSeriesEntry.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(UniqueUsersTimeSeriesEntry.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => UniqueUsersTimeSeriesEntry.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
