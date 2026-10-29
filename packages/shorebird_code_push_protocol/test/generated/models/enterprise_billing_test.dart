// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('EnterpriseBilling', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = EnterpriseBilling(
        hasBillingAccount: false,
        plan: EnterpriseBillingPlan1(
          name: 'example',
          level: 'example',
          currentPeriodStart: DateTime.utc(2024),
          currentPeriodEnd: DateTime.utc(2024),
          cancelAtPeriodEnd: false,
          currency: 'example',
        ),
        position: const AccountPosition(
          includedInstalls: 0,
          installs: 0,
          includedInstallsUsed: 0,
          includedExhausted: false,
          overageInstalls: 0,
          installCeiling: 0,
          remainingInstalls: 0,
          atCeiling: false,
          nearingLimit: false,
          consumingOverage: false,
          accruedOverageAmount: 'example',
        ),
      );
      final parsed = EnterpriseBilling.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(EnterpriseBilling.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => EnterpriseBilling.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
