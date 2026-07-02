// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RolloutArtifactType', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = RolloutArtifactType.values.first;
      final parsed = RolloutArtifactType.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RolloutArtifactType.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RolloutArtifactType.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in RolloutArtifactType.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in RolloutArtifactType.values) {
        expect(RolloutArtifactType.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
