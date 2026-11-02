// GENERATED — do not hand-edit.
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('CreateServiceAccountTrustRuleRequest', () {
    test('round-trips via maybeFromJson/toJson', () {
      const instance = CreateServiceAccountTrustRuleRequest(
        provider: TrustRuleProvider.github,
        repositoryOwner: 'example',
        repositoryName: 'example',
        workflowPath: 'example',
      );
      final parsed = CreateServiceAccountTrustRuleRequest.maybeFromJson(
        instance.toJson(),
      )!;
      expect(parsed, equals(instance));
      expect(parsed.hashCode, equals(instance.hashCode));
    });

    test('maybeFromJson returns null on null input', () {
      expect(CreateServiceAccountTrustRuleRequest.maybeFromJson(null), isNull);
    });

    test('maybeFromJson throws FormatException on invalid input', () {
      expect(
        () => CreateServiceAccountTrustRuleRequest.maybeFromJson(
          <String, dynamic>{},
        ),
        throwsFormatException,
      );
    });
  });
}
