// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('MetricsRange', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = MetricsRange(
        start: DateTime.utc(2024),
        end: DateTime.utc(2024),
      );
      final parsed = MetricsRange.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(MetricsRange.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => MetricsRange.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
