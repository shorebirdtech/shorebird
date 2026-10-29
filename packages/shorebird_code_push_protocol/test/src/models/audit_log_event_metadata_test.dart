import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(AuditLogEventMetadata, () {
    const json = {
      'version': '1.9.0',
      'product': {'name': 'Shorebird', 'vendor_name': 'Shorebird'},
      'uid': '501',
      'log_name': 'audit',
    };

    // An event above any organization, such as an enterprise's creation,
    // belongs to the enterprise alone, and the server sends no tenant_uid.
    test('reads an entry with no organization', () {
      final metadata = AuditLogEventMetadata.fromJson(json);
      expect(metadata.tenantUid, isNull);
      expect(metadata.toJson(), isNot(contains('tenant_uid')));
    });

    test("reads an organization's entry", () {
      final metadata = AuditLogEventMetadata.fromJson({
        ...json,
        'tenant_uid': '42',
      });
      expect(metadata.tenantUid, '42');
    });
  });
}
