// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RolloutStep', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = RolloutStep(percentage: 0);
      final parsed = RolloutStep.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RolloutStep.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RolloutStep.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
