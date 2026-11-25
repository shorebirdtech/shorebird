// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchLink', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = PatchLink(result: 'example');
      final parsed = PatchLink.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchLink.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchLink.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
