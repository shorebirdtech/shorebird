// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseSizeSummary', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = ReleaseSizeSummary(
        platform: ReleasePlatform.android,
        status: SizeAnalysisStatus.succeeded,
        engineVersion: 'example',
        analyzedAt: DateTime.utc(2024),
        totalSizeInBytes: 0,
        dartSizeInBytes: 0,
        nativeSizeInBytes: 0,
        assetSizeInBytes: 0,
      );
      final parsed = ReleaseSizeSummary.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ReleaseSizeSummary.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ReleaseSizeSummary.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
