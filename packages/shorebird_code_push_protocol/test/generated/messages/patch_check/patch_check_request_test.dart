// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchCheckRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = PatchCheckRequest(
        releaseVersion: 'example',
        platform: ReleasePlatform.values.first,
        arch: 'example',
        appId: 'example',
        channel: 'example',
      );
      final parsed = PatchCheckRequest.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchCheckRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchCheckRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
