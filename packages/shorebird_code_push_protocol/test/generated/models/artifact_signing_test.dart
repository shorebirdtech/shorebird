// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ArtifactSigning', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ArtifactSigning(mode: 'example');
      final parsed = ArtifactSigning.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ArtifactSigning.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ArtifactSigning.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
