// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseStatus', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ReleaseStatus.values.first;
      final parsed = ReleaseStatus.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ReleaseStatus.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ReleaseStatus.maybeFromJson('__invalid_enum_value__'),
        throwsFormatException,
      );
    });
  });
}
