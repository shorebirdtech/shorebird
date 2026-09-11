// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityHeatmapCell', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ActivityHeatmapCell(
        dayOfWeekUtc: 0,
        hourUtc: 0,
        averageActiveDevices: 0,
      );
      final parsed = ActivityHeatmapCell.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ActivityHeatmapCell.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ActivityHeatmapCell.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
