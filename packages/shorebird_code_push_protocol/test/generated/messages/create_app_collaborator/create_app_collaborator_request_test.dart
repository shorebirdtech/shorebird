// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateAppCollaboratorRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreateAppCollaboratorRequest(email: 'user@example.com');
      final parsed = CreateAppCollaboratorRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateAppCollaboratorRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateAppCollaboratorRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
