// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateOrganizationInvitation201Response', () {
    test('CreateInvitationResponse round-trips via maybeFromJson/toJson', () {
      const instance = CreateInvitationResponse(email: 'example');
      final parsed = CreateInvitationResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('AddedMemberResponse round-trips via maybeFromJson/toJson', () {
      const instance = AddedMemberResponse(email: 'example', role: Role.owner);
      final parsed = AddedMemberResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(
        CreateOrganizationInvitation201Response.maybeFromJson(null),
        isNull,
      );
    });
  });
}
