import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ArtifactUploadMethod, () {
    test('round-trips through json', () {
      for (final method in ArtifactUploadMethod.values) {
        expect(ArtifactUploadMethod.fromJson(method.toJson()), equals(method));
      }
    });

    test('maybeFromJson returns null for null', () {
      expect(ArtifactUploadMethod.maybeFromJson(null), isNull);
    });

    test('fromJson throws on an unknown value', () {
      expect(
        () => ArtifactUploadMethod.fromJson('nope'),
        throwsFormatException,
      );
    });
  });
}
