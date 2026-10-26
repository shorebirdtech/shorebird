// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogProduct', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogProduct(name: 'example', vendorName: 'example');
      final parsed = AuditLogProduct.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogProduct.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AuditLogProduct.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
