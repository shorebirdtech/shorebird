// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('UniqueUsersWindow', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = UniqueUsersWindow(
        uniqueUsers: 0,
        range: MetricsRange(
          start: DateTime.utc(2024),
          end: DateTime.utc(2024),
        ),
      );
      final parsed = UniqueUsersWindow.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(UniqueUsersWindow.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => UniqueUsersWindow.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
