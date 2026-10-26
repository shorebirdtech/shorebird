// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogSourceEndpoint', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogSourceEndpoint();
      final parsed = AuditLogSourceEndpoint.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogSourceEndpoint.maybeFromJson(null), isNull);
    });
  });
}
