// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogEventMetadata', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogEventMetadata(
        version: 'example',
        product: AuditLogProduct(name: 'example', vendorName: 'example'),
        uid: 'example',
      );
      final parsed = AuditLogEventMetadata.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogEventMetadata.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AuditLogEventMetadata.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
