// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseMembership', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseMembership(
        id: 0,
        name: 'example',
        role: EnterpriseRole.owner,
      );
      final parsed = EnterpriseMembership.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseMembership.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseMembership.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
