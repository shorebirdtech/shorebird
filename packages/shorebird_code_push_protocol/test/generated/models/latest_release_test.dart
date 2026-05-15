// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('LatestRelease', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = LatestRelease(
        id: 0,
        version: 'example',
        flutterRevision: 'example',
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
        status: ReleaseStatus.values.first,
        analysis: const ReleaseAnalysis(
          displayName: 'example',
          packageName: 'example',
          minSdkVersion: 'example',
          targetSdkVersion: 'example',
          architectures: <String>['example'],
        ),
      );
      final parsed = LatestRelease.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(LatestRelease.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => LatestRelease.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
