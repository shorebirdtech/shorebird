// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('GetGcpUploadSpeedTestUrl200Response', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = GetGcpUploadSpeedTestUrl200Response(
        uploadUrl: 'example',
      );
      final parsed = GetGcpUploadSpeedTestUrl200Response.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(GetGcpUploadSpeedTestUrl200Response.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => GetGcpUploadSpeedTestUrl200Response.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
