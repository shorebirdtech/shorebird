// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetActivityHeatmapResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetActivityHeatmapResponse(
        cells: <ActivityHeatmapCell>[
          ActivityHeatmapCell(
            dayOfWeekUtc: 0,
            hourUtc: 0,
            averageActiveDevices: 0,
          ),
        ],
        busiestDayOfWeekUtc: 0,
        busiestHourUtc: 0,
        lookbackDays: 0,
        asOf: DateTime.utc(2024),
      );
      final parsed = GetActivityHeatmapResponse.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetActivityHeatmapResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetActivityHeatmapResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
