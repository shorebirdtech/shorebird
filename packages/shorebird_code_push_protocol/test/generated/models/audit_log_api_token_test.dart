// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogApiToken', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogApiToken(uid: 'example');
      final parsed = AuditLogApiToken.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogApiToken.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AuditLogApiToken.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
