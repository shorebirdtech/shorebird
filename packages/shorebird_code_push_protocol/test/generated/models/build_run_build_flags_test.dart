// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('BuildRunBuildFlags', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = BuildRunBuildFlags(
        dartDefineCount: 0,
        dartDefines: {'key': 'example'},
      );
      final parsed = BuildRunBuildFlags.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(BuildRunBuildFlags.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => BuildRunBuildFlags.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
