import 'package:mocktail/mocktail.dart';
import 'package:shorebird_cli/src/code_push_client_wrapper.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';

/// Organization 42, which the user owns.
final auditLogMembership = OrganizationMembership(
  organization: Organization(
    id: 42,
    name: 'Acme Corp',
    organizationType: OrganizationType.team,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  ),
  role: Role.owner,
);

/// An `organization.rename` entry at 2026-10-20 14:03:22 UTC, with entry id
/// [uid], caused by [user] (alice@acme.com, id 12, by default).
AuditLogEvent auditLogEntry({
  String uid = '1',
  Map<String, dynamic> user = const {
    'uid': '12',
    'email_addr': 'alice@acme.com',
    'type_id': 1,
    'type': 'User',
  },
}) => AuditLogEvent.fromJson({
  'class_uid': 6003,
  'category_uid': 6,
  'activity_id': 3,
  'type_uid': 600303,
  'time': DateTime.utc(2026, 10, 20, 14, 3, 22).millisecondsSinceEpoch,
  'severity_id': 1,
  'status_id': 1,
  'metadata': {
    'version': '1.9.0',
    'product': const {'name': 'Shorebird', 'vendor_name': 'Shorebird'},
    'uid': uid,
    'tenant_uid': '42',
    'log_name': 'audit',
  },
  'api': const {'operation': 'organization.rename'},
  'actor': {'user': user},
  'src_endpoint': const {'ip': '203.0.113.7'},
  'resources': const [
    {'type': 'organization', 'uid': '42'},
  ],
  'unmapped': const <String, dynamic>{},
});

/// The audit log fetch on [wrapper], with any arguments.
Future<GetOrganizationAuditLogsResponse> anyAuditLogFetch(
  CodePushClientWrapper wrapper,
) => wrapper.getOrganizationAuditLogs(
  organizationId: any(named: 'organizationId'),
  perPage: any(named: 'perPage'),
  cursor: any(named: 'cursor'),
  order: any(named: 'order'),
  startDate: any(named: 'startDate'),
  endDate: any(named: 'endDate'),
  appId: any(named: 'appId'),
  actorId: any(named: 'actorId'),
  operation: any(named: 'operation'),
);

/// Makes [wrapper] answer an audit log fetch with the page for its cursor
/// in [pages] (null for the first page), throwing [failAt]'s error when
/// asked for that cursor.
void stubAuditLogPages(
  CodePushClientWrapper wrapper,
  Map<String?, GetOrganizationAuditLogsResponse> pages, {
  ({String? cursor, Exception error})? failAt,
}) {
  when(() => anyAuditLogFetch(wrapper)).thenAnswer((invocation) async {
    final cursor = invocation.namedArguments[#cursor] as String?;
    if (failAt != null && failAt.cursor == cursor) throw failAt.error;
    return pages[cursor]!;
  });
}

/// The entry ids of [entries], as JSON.
List<String> entryIds(List<dynamic> entries) => [
  for (final e in entries.cast<Map<String, dynamic>>())
    (e['metadata'] as Map)['uid'] as String,
];
