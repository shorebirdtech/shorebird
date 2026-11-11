// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('SetPatchRolloutRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = SetPatchRolloutRequest(rolloutPercentage: 0);
      final parsed = SetPatchRolloutRequest.maybeFromJson(instance.toJson());
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(SetPatchRolloutRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => SetPatchRolloutRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
