// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PrivateUser', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = PrivateUser(
        id: 0,
        email: 'user@example.com',
        jwtIssuer: 'example',
      );
      final parsed = PrivateUser.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PrivateUser.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PrivateUser.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
