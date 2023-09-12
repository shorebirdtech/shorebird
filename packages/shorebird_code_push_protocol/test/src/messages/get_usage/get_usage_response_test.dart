import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(GetUsageResponse, () {
    test('can be (de)serialized', () {
      final response = GetUsageResponse(
        plan: ShorebirdPlan(
          name: 'Hobby',
          monthlyCost: Money.fromIntWithCurrency(0, usd),
          currency: 'USD',
          patchInstallLimit: 1000,
          maxTeamSize: 1,
        ),
        apps: [
          const AppUsage(id: 'app-id', name: 'My app', patchInstallCount: 1337),
        ],
        currentPeriodCost: Money.fromIntWithCurrency(0, usd),
        currentPeriodStart: DateTime(2021),
        currentPeriodEnd: DateTime(2021, 1, 2),
        cancelAtPeriodEnd: false,
      );
      expect(
        GetUsageResponse.fromJson(response.toJson()).toJson(),
        equals(response.toJson()),
      );
    });
  });
}
