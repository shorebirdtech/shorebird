// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseTeamAccess', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseTeamAccess(teamId: 0, role: Role.owner);
      final parsed = EnterpriseTeamAccess.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseTeamAccess.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseTeamAccess.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
