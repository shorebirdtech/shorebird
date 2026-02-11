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
        mauInsightEnabled: true,
        availableRoles: {
          Role.admin: [
            'apps.view',
            'releases.view',
            'patches.view',
            'channels.view',
            'organizations.view',
            'organizationApps.view',
            'organizationMembers.view',
            'appRoleGrants.view',
            'insights.view',
            'plans.view',
          ],
          Role.developer: [
            'apps.view',
            'releases.view',
            'patches.view',
            'channels.view',
            'organizations.view',
            'organizationApps.view',
            'organizationMembers.view',
          ],
        },
      );

      expect(Plan.fromJson(plan.toJson()).toJson(), equals(plan.toJson()));
    });
  });
}
