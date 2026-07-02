// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RolloutIneligibleReason', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = RolloutIneligibleReason.values.first;
      final parsed = RolloutIneligibleReason.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RolloutIneligibleReason.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RolloutIneligibleReason.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in RolloutIneligibleReason.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in RolloutIneligibleReason.values) {
        expect(RolloutIneligibleReason.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
