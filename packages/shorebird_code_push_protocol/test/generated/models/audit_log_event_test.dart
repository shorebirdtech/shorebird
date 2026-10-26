// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AuditLogEvent', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AuditLogEvent(
        activityId: 0,
        typeUid: 0,
        time: 0,
        metadata: AuditLogEventMetadata(
          version: 'example',
          product: AuditLogProduct(name: 'example', vendorName: 'example'),
          uid: 'example',
          tenantUid: 'example',
        ),
        api: AuditLogApi(operation: 'example'),
        actor: AuditLogActor(
          user: AuditLogActorUser(typeId: 0, type: AuditLogActorUserType.user),
        ),
        srcEndpoint: AuditLogSourceEndpoint(),
        resources: <AuditLogResource>[
          AuditLogResource(type: 'example', uid: 'example'),
        ],
        unmapped: {'key': <String, dynamic>{}},
      );
      final parsed = AuditLogEvent.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AuditLogEvent.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AuditLogEvent.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
