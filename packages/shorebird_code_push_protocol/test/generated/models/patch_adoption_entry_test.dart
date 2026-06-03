// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchAdoptionEntry', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PatchAdoptionEntry(
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
      );
      final parsed = PatchAdoptionEntry.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchAdoptionEntry.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchAdoptionEntry.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
