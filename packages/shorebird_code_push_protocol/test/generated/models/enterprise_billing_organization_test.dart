// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseBillingOrganization', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = EnterpriseBillingOrganization(
        id: 0,
        name: 'example',
        appCount: 0,
        patchInstalls: 0,
      );
      final parsed = EnterpriseBillingOrganization.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseBillingOrganization.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseBillingOrganization.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
