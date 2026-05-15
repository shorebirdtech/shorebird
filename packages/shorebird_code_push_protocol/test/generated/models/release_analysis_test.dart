// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('ReleaseAnalysis', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = ReleaseAnalysis(
        displayName: 'example',
        packageName: 'example',
        minSdkVersion: 'example',
        targetSdkVersion: 'example',
        architectures: <String>['example'],
      );
      final parsed = ReleaseAnalysis.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(ReleaseAnalysis.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => ReleaseAnalysis.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
