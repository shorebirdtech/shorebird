// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AppCollaborator', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AppCollaborator(
        userId: 0,
        email: 'user@example.com',
        role: Role.owner,
      );
      final parsed = AppCollaborator.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AppCollaborator.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AppCollaborator.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
