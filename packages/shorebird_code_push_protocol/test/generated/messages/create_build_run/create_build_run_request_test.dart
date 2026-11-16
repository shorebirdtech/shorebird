// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateBuildRunRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      final instance = CreateBuildRunRequest(
        runId: 'example',
        command: BuildRunCommand.release,
        platform: ReleasePlatform.android,
        outcome: BuildRunOutcome.succeeded,
        startedAt: DateTime.utc(2024),
        durationMs: 0,
        dryRun: false,
      );
      final parsed = CreateBuildRunRequest.maybeFromJson(instance.toJson())!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateBuildRunRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateBuildRunRequest.maybeFromJson(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
