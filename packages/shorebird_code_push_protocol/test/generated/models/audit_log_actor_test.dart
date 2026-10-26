// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogActor', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogActor(
        user: AuditLogActorUser(typeId: 0, type: AuditLogActorUserType.user),
      );
      final parsed = AuditLogActor.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogActor.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AuditLogActor.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
