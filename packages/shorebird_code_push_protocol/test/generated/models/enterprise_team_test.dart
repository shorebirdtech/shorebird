// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseTeam', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseTeam(
        id: 0,
        name: 'example',
        memberCount: 0,
        appCount: 0,
        defaultRole: EnterpriseDefaultRole.viewer,
        apps: <EnterpriseAppSummary>[
          EnterpriseAppSummary(id: 'example', displayName: 'example'),
        ],
      );
      final parsed = EnterpriseTeam.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseTeam.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseTeam.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
