// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogActorUser', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogActorUser(
        typeId: 0,
        type: AuditLogActorUserType.user,
      );
      final parsed = AuditLogActorUser.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogActorUser.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AuditLogActorUser.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
