import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(Subscription, () {
    final plan = ShorebirdPlan(
      name: 'Hobby',
      monthlyCost: Money.fromIntWithCurrency(0, usd),
      patchInstallLimit: 1000,
      maxTeamSize: 1,
    );

    test('can be (de)serialized', () {
      final subscription = Subscription(
        plan: plan,
        cost: 100,
        paidThroughDate: DateTime.now(),
        willRenew: true,
      );
      expect(
        Subscription.fromJson(subscription.toJson()).toJson(),
        equals(subscription.toJson()),
      );
    });

    group('isActive', () {
      test('returns true if paidThroughDate is in the future', () {
        final subscription = Subscription(
          plan: plan,
          cost: 100,
          paidThroughDate: DateTime.now().add(const Duration(days: 1)),
          willRenew: true,
        );
        expect(subscription.isActive, isTrue);
      });

      test('returns false if paidThroughDate is in the past', () {
        final subscription = Subscription(
          plan: plan,
          cost: 100,
          paidThroughDate: DateTime.now().subtract(const Duration(days: 1)),
          willRenew: true,
        );
        expect(subscription.isActive, isFalse);
      });
    });
  });
}
