// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('RunArtifactSharedBy', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = RunArtifactSharedBy.setting;
      final parsed = RunArtifactSharedBy.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(RunArtifactSharedBy.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => RunArtifactSharedBy.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });

    test('toString matches toJson for every value', () {
      for (final value in RunArtifactSharedBy.values) {
        expect(value.toString(), equals(value.toJson()));
      }
    });

    test('fromJson round-trips every value', () {
      for (final value in RunArtifactSharedBy.values) {
        expect(RunArtifactSharedBy.fromJson(value.toJson()), equals(value));
      }
    });
  });
}
