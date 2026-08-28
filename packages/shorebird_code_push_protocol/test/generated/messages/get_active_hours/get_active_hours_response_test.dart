// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetActiveHoursResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetActiveHoursResponse(
        hourly: const <ActiveHourEntry>[
          ActiveHourEntry(hourUtc: 0, averageActiveDevices: 0),
        ],
        recommendedWindowStartUtc: 0,
        recommendedWindowLengthHours: 0,
        busiestHourUtc: 0,
        lookbackDays: 0,
        asOf: DateTime.utc(2024),
      );
      final parsed = GetActiveHoursResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetActiveHoursResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetActiveHoursResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
