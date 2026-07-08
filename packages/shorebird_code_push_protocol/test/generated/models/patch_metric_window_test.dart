// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchMetricWindow', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PatchMetricWindow(
        count: 0,
        range: MetricsRange(
          start: DateTime.utc(2024),
          end: DateTime.utc(2024),
        ),
      );
      final parsed = PatchMetricWindow.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchMetricWindow.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchMetricWindow.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
