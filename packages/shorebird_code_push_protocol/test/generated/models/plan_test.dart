// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Plan', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = Plan(
        name: 'example',
        currency: 'example',
        basePrice: 0,
        baseInstallCount: 0,
        patchInstallCredit: 0,
        patchOverageLimit: 0,
        pricePerOverageInstall: 'example',
        currentPeriodStart: DateTime.utc(2024),
        currentPeriodEnd: DateTime.utc(2024),
        cancelAtPeriodEnd: false,
        isTiered: false,
        isTrial: false,
        baseStanding: 'example',
        overageStanding: 'example',
        overageState: 'example',
        overageBlockedBy: 'example',
        overagePeriodStart: DateTime.utc(2024),
        overagePeriodEnd: DateTime.utc(2024),
        features: const <String>['example'],
        level: 'example',
        minimumReleasesKept: 0,
        maxTeamSize: 0,
        availableRoles: const <Role>[Role.owner],
        billingInterval: 'example',
        billingIntervalCount: 0,
        subscriberSince: DateTime.utc(2024),
      );
      final parsed = Plan.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(Plan.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => Plan.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
