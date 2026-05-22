// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetVersionDistributionResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetVersionDistributionResponse(
        entries: const <VersionDistributionEntry>[
          VersionDistributionEntry(
            releaseVersion: 'example',
            deviceCount: 0,
            percentage: 0,
          ),
        ],
        totalDevices: 0,
        activeWindowDays: 0,
        asOf: DateTime.utc(2024),
      );
      final parsed = GetVersionDistributionResponse.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetVersionDistributionResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetVersionDistributionResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
