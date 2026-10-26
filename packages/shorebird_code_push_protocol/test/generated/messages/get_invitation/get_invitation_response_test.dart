// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetInvitationResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetInvitationResponse(
        id: '00000000-0000-0000-0000-000000000000',
        organizationId: 0,
        appId: 'example',
        targetName: 'example',
        inviterEmail: 'example',
        email: 'example',
        role: Role.owner,
        expiresAt: DateTime.utc(2024),
      );
      final parsed = GetInvitationResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetInvitationResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetInvitationResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
