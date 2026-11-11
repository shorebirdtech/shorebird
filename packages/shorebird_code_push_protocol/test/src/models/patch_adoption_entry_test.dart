import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(PatchAdoptionEntry, () {
    test('can be (de)serialized with rolled-back platforms', () {
      const entry = PatchAdoptionEntry(
        patchNumber: 7,
        targetPlatforms: [ReleasePlatform.android, ReleasePlatform.ios],
        isRolledBack: false,
        rolledBackPlatforms: [ReleasePlatform.ios],
        series: [],
      );
      final json = entry.toJson();
      expect(json['rolled_back_platforms'], equals(['ios']));
      expect(PatchAdoptionEntry.fromJson(json), equals(entry));
    });
  });
}
