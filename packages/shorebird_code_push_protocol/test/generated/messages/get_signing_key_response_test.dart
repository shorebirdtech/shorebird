// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetSigningKeyResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetSigningKeyResponse(
        signingKey: SigningKey(id: 0, publicKeyPem: 'example'),
      );
      final parsed = GetSigningKeyResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetSigningKeyResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetSigningKeyResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
