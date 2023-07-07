import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdPlan, () {
    test('can be (de)serialized', () {
      const plan = ShorebirdPlan(
        name: 'Hobby',
        monthlyCost: 0,
        patchInstallLimit: 1000,
        maxTeamSize: 1,
      );
      expect(
        ShorebirdPlan.fromJson(plan.toJson()).toJson(),
        equals(plan.toJson()),
      );
    });
  });
}
