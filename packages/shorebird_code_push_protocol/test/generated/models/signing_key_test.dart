// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SigningKey', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = SigningKey(id: 0, publicKeyPem: 'example');
      final parsed = SigningKey.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(SigningKey.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => SigningKey.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
