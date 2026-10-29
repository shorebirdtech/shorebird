// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseBillingPlan1', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = EnterpriseBillingPlan1(
        name: 'example',
        level: 'example',
        currentPeriodStart: DateTime.utc(2024),
        currentPeriodEnd: DateTime.utc(2024),
        cancelAtPeriodEnd: false,
        currency: 'example',
      );
      final parsed = EnterpriseBillingPlan1.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseBillingPlan1.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseBillingPlan1.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
