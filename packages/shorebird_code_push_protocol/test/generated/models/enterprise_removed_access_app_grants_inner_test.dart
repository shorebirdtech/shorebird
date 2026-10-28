// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseRemovedAccessAppGrantsInner', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseRemovedAccessAppGrantsInner(
        appId: 'example',
        organizationId: 0,
        role: Role.owner,
      );
      final parsed = EnterpriseRemovedAccessAppGrantsInner.maybeFromJson(
        instance.toJson(),
      );
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseRemovedAccessAppGrantsInner.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseRemovedAccessAppGrantsInner.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
