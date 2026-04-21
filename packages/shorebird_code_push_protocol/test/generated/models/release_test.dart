// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Release', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = Release(
        id: 0,
        appId: 'example',
        version: 'example',
        flutterRevision: 'example',
        platformStatuses: {
          ReleasePlatform.values.first: ReleaseStatus.values.first,
        },
        createdAt: DateTime.utc(2024),
        updatedAt: DateTime.utc(2024),
      );
      final parsed = Release.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(Release.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => Release.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
