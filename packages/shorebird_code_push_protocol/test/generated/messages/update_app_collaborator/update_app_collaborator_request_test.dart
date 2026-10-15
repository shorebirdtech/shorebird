// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('UpdateAppCollaboratorRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = UpdateAppCollaboratorRequest(
        role: AppCollaboratorRole.admin,
      );
      final parsed = UpdateAppCollaboratorRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(UpdateAppCollaboratorRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => UpdateAppCollaboratorRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
