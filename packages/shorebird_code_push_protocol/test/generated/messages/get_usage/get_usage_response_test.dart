// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetUsageResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetUsageResponse(
        apps: <AppUsage>[
          AppUsage(id: 'example', name: 'example', patchInstallCount: 0),
        ],
        position: AccountPosition(
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
        reportedOverage: 0,
      );
      final parsed = GetUsageResponse.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetUsageResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetUsageResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
