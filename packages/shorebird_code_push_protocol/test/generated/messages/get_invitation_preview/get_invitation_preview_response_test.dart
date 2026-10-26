// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetInvitationPreviewResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetInvitationPreviewResponse(
        targetName: 'example',
        type: InvitationTargetType.organization,
      );
      final parsed = GetInvitationPreviewResponse.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetInvitationPreviewResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetInvitationPreviewResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
