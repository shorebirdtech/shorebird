// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetPatchMetricResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetPatchMetricResponse(
        asOf: DateTime.utc(2024),
        granularity: 'example',
        current: PatchMetricCurrentWindow(
          count: 0,
          range: MetricsRange(
            start: DateTime.utc(2024),
            end: DateTime.utc(2024),
          ),
        ),
      );
      final parsed = GetPatchMetricResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetPatchMetricResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetPatchMetricResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
