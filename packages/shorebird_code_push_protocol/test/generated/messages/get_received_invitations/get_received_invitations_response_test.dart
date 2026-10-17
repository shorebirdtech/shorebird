// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetReceivedInvitationsResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetReceivedInvitationsResponse(
        invitations: <ReceivedInvitation>[
          ReceivedInvitation(
            id: '00000000-0000-0000-0000-000000000000',
            targetName: 'example',
            inviterEmail: 'example',
            role: Role.owner,
            createdAt: DateTime.utc(2024),
            expiresAt: DateTime.utc(2024),
          ),
        ],
      );
      final parsed = GetReceivedInvitationsResponse.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetReceivedInvitationsResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetReceivedInvitationsResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
