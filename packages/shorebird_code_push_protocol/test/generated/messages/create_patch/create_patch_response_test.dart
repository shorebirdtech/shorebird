// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreatePatchResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreatePatchResponse(id: 0, number: 0);
      final parsed = CreatePatchResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreatePatchResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreatePatchResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
