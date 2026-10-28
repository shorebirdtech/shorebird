// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('AppUsage', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = AppUsage(
        id: 'example',
        name: 'example',
        patchInstallCount: 0,
      );
      final parsed = AppUsage.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(AppUsage.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => AppUsage.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
