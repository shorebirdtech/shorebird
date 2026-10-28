// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseAppGrant', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseAppGrant(appId: 'example', role: Role.owner);
      final parsed = EnterpriseAppGrant.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseAppGrant.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseAppGrant.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
