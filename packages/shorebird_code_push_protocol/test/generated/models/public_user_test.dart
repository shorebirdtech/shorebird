// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PublicUser', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = PublicUser(id: 0, email: 'user@example.com');
      final parsed = PublicUser.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PublicUser.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PublicUser.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
