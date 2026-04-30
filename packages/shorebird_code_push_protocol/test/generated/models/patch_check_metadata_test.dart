// Some OpenAPI specs flatten inline schemas into class names long
// enough that `dart format` can't keep imports and call sites under
// 80 cols as bare identifiers.
// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('PatchCheckMetadata', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = PatchCheckMetadata(
        number: 0,
        downloadUrl: 'example',
        hash: 'example',
      );
      final parsed = PatchCheckMetadata.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(PatchCheckMetadata.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => PatchCheckMetadata.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
