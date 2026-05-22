// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('VersionDistributionEntry', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = VersionDistributionEntry(
        releaseVersion: 'example',
        deviceCount: 0,
        percentage: 0,
      );
      final parsed = VersionDistributionEntry.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(VersionDistributionEntry.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => VersionDistributionEntry.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
