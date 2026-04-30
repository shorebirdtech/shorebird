// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetGcpDownloadSpeedTestUrl200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetGcpDownloadSpeedTestUrl200Response(
        downloadUrl: 'example',
      );
      final parsed = GetGcpDownloadSpeedTestUrl200Response.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetGcpDownloadSpeedTestUrl200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetGcpDownloadSpeedTestUrl200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
