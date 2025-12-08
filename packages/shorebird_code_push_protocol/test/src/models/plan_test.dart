import 'package:decimal/decimal.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(Plan, () {
    test('can be (de)serialized', () {
      final plan = Plan(
        name: 'name',
        currency: 'currency',
        basePrice: 42,
        baseInstallCount: 42,
        currentPeriodStart: DateTime.now(),
        currentPeriodEnd: DateTime.now(),
        cancelAtPeriodEnd: true,
        isTiered: true,
        maxTeamSize: 42,
        pricePerOverageInstall: Decimal.fromInt(10),
        isTrial: true,
        availableRoles: [Role.admin, Role.developer],
      );

      expect(Plan.fromJson(plan.toJson()).toJson(), equals(plan.toJson()));
    });
  });
}
