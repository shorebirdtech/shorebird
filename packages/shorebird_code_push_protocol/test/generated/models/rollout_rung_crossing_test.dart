// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RolloutRungCrossing', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = RolloutRungCrossing(
        rung: 0,
        crossedAt: DateTime.utc(2024),
      );
      final parsed = RolloutRungCrossing.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RolloutRungCrossing.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RolloutRungCrossing.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
