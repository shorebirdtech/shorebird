import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/shorebird_version.dart';
import 'package:shorebird_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../helpers.dart';
import '../mocks.dart';

void main() {
  useTempWorkingDirectory();
  group('ShorebirdVersionValidator', () {
    late ShorebirdVersion shorebirdVersion;
    late ShorebirdVersionValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {shorebirdVersionRef.overrideWith(() => shorebirdVersion)},
      );
    }

    setUp(() {
      shorebirdVersion = MockShorebirdVersion();
      validator = ShorebirdVersionValidator();

      when(shorebirdVersion.hasUpstream).thenAnswer((_) async => true);
      when(
        () => shorebirdVersion.noUpstreamMessage,
      ).thenReturn('Shorebird is not on a branch that receives updates.');
      when(shorebirdVersion.isLatest).thenAnswer((_) async => false);
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('canRunInContext always returns true', () {
      expect(validator.canRunInCurrentContext(), isTrue);
    });

    test('returns no issues when shorebird is up-to-date', () async {
      when(shorebirdVersion.isLatest).thenAnswer((_) async => true);

      final results = await runWithOverrides(validator.validate);

      expect(results, isEmpty);
    });

    test('warns how to get updates when shorebird has no upstream', () async {
      when(shorebirdVersion.hasUpstream).thenAnswer((_) async => false);

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(
        results.first.message,
        'Shorebird is not on a branch that receives updates.',
      );
      verifyNever(shorebirdVersion.isLatest);
    });

    test('returns an error when the upstream cannot be determined', () async {
      when(shorebirdVersion.hasUpstream).thenThrow(
        const ProcessException(
          'git',
          [
            'rev-parse',
            '-q',
            '--verify',
            '@{upstream}',
          ],
          'fatal: detected dubious ownership in repository',
          128,
        ),
      );

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.error);
      expect(results.first.message, contains('dubious ownership'));
    });

    test(
      'returns an error when shorebird version cannot be determined',
      () async {
        when(
          shorebirdVersion.isLatest,
        ).thenThrow(const ProcessException('git', ['rev-parse', 'HEAD']));

        final results = await runWithOverrides(validator.validate);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(
          results.first.message,
          contains('Failed to get shorebird version'),
        );
      },
    );

    test('returns a warning when a newer shorebird is available', () async {
      when(shorebirdVersion.isLatest).thenAnswer((_) async => false);

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(
        results.first.message,
        contains('A new version of shorebird is available!'),
      );
    });
  });
}
