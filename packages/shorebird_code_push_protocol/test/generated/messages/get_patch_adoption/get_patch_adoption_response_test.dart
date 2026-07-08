// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetPatchAdoptionResponse', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = GetPatchAdoptionResponse(
        releaseVersion: 'example',
        isLatest: false,
        granularity: 'example',
        range: MetricsRange(
          start: DateTime.utc(2024),
          end: DateTime.utc(2024),
        ),
        asOf: DateTime.utc(2024),
        patches: <PatchAdoptionEntry>[
          PatchAdoptionEntry(
            patchNumber: 0,
            targetPlatforms: <ReleasePlatform>[ReleasePlatform.values.first],
            isRolledBack: false,
            series: <PatchAdoptionPoint>[
              PatchAdoptionPoint(
                period: DateTime.utc(2024),
                devices: 0,
                target: 0,
                adoptionPct: 0,
              ),
            ],
          ),
        ],
      );
      final parsed = GetPatchAdoptionResponse.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetPatchAdoptionResponse.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetPatchAdoptionResponse.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
