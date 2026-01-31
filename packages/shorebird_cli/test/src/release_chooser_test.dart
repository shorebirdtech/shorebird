import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/logging/logging.dart';
import 'package:shorebird_cli/src/release_chooser.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:test/test.dart';

import 'mocks.dart';

Release _release(String version, DateTime createdAt) {
  return Release(
    id: version.hashCode,
    appId: 'app',
    version: version,
    flutterRevision: 'rev',
    flutterVersion: null,
    displayName: null,
    platformStatuses: const {},
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

void main() {
  group('chooseRelease', () {
    late ShorebirdLogger logger;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {loggerRef.overrideWith(() => logger)},
      );
    }

    setUp(() {
      logger = MockShorebirdLogger();
    });

    test('returns single release without prompting', () {
      final release = _release('1.0.0', DateTime(2025, 3, 15));

      final result = runWithOverrides(
        () => chooseRelease(
          releases: [release],
          action: 'patch',
        ),
      );

      expect(result, equals(release));
      verify(
        () => logger.info('Using release 1.0.0  (Mar 15)'),
      ).called(1);
      verifyNever(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      );
    });

    test('sorts releases newest first', () {
      final old = _release('1.0.0', DateTime(2025));
      final mid = _release('1.1.0', DateTime(2025, 6));
      final newest = _release('1.2.0', DateTime(2026));

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(newest);

      runWithOverrides(
        () => chooseRelease(
          releases: [mid, old, newest],
          action: 'patch',
        ),
      );

      final captured =
          verify(
                () => logger.chooseOne<Release>(
                  'Which release would you like to patch?',
                  choices: captureAny(named: 'choices'),
                  display: any(named: 'display'),
                ),
              ).captured.first
              as List<Release>;

      expect(captured.first.version, equals('1.2.0'));
      expect(captured.last.version, equals('1.0.0'));
    });

    test('displays version with date', () {
      final release = _release('1.2.3', DateTime(2025, 3, 15));
      final other = _release('1.2.2', DateTime(2025, 3, 1));

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenReturn(release);

      runWithOverrides(
        () => chooseRelease(
          releases: [release, other],
          action: 'preview',
        ),
      );

      final verification = verify(
        () => logger.chooseOne<Release>(
          'Which release would you like to preview?',
          choices: any(named: 'choices'),
          display: captureAny(named: 'display'),
        ),
      );
      final displayFn =
          verification.captured.first as String Function(Release);
      expect(displayFn(release), equals('1.2.3  (Mar 15)'));
    });

    test('shows truncated list when more than 10 releases', () {
      final releases = List.generate(
        15,
        (i) => _release('1.0.$i', DateTime(2025, 1, i + 1)),
      );

      var callCount = 0;
      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenAnswer((invocation) {
        final choices =
            invocation.namedArguments[#choices] as List<Release>;
        callCount++;
        if (callCount == 1) {
          // 10 releases + 1 "show all" sentinel = 11.
          expect(choices, hasLength(11));
          expect(
            identical(choices.last, showAllReleaseSentinel),
            isTrue,
          );
          // Return the sentinel to trigger "show all".
          return choices.last;
        }
        // Second call: all 15 releases.
        expect(choices, hasLength(15));
        return choices.first;
      });

      final result = runWithOverrides(
        () => chooseRelease(
          releases: releases,
          action: 'patch',
        ),
      );

      expect(result, isA<Release>());
      expect(identical(result, showAllReleaseSentinel), isFalse);
      expect(callCount, equals(2));
    });

    test('returns directly when user picks from truncated list', () {
      final releases = List.generate(
        15,
        (i) => _release('1.0.$i', DateTime(2025, 1, i + 1)),
      );

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenAnswer((invocation) {
        final choices =
            invocation.namedArguments[#choices] as List<Release>;
        // Return a real release, not the sentinel.
        return choices.first;
      });

      final result = runWithOverrides(
        () => chooseRelease(
          releases: releases,
          action: 'patch',
        ),
      );

      expect(result, isA<Release>());
      verify(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).called(1);
    });

    test('shows all 11 releases without truncation', () {
      // 11 releases = maxDisplayedReleases + 1, so truncation would not
      // save any lines (10 + sentinel = 11 lines vs 11 lines).
      final releases = List.generate(
        11,
        (i) => _release('1.0.$i', DateTime(2025, 1, i + 1)),
      );

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenAnswer((invocation) {
        final choices =
            invocation.namedArguments[#choices] as List<Release>;
        expect(choices, hasLength(11));
        expect(
          choices.every((r) => !identical(r, showAllReleaseSentinel)),
          isTrue,
        );
        return choices.first;
      });

      runWithOverrides(
        () => chooseRelease(
          releases: releases,
          action: 'patch',
        ),
      );

      verify(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).called(1);
    });

    test('skips truncation when 10 or fewer releases', () {
      final releases = List.generate(
        5,
        (i) => _release('1.0.$i', DateTime(2025, 1, i + 1)),
      );

      when(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).thenAnswer((invocation) {
        final choices =
            invocation.namedArguments[#choices] as List<Release>;
        expect(choices, hasLength(5));
        // No sentinel present.
        expect(
          choices.every((r) => !identical(r, showAllReleaseSentinel)),
          isTrue,
        );
        return choices.first;
      });

      runWithOverrides(
        () => chooseRelease(
          releases: releases,
          action: 'patch',
        ),
      );

      verify(
        () => logger.chooseOne<Release>(
          any(),
          choices: any(named: 'choices'),
          display: any(named: 'display'),
        ),
      ).called(1);
    });

    group('formatReleaseDisplay', () {
      test('formats release with version and date', () {
        final release = _release('2.0.1', DateTime(2025, 12, 25));
        expect(
          formatReleaseDisplay(release, totalCount: 5),
          equals('2.0.1  (Dec 25)'),
        );
      });

      test('formats show all sentinel', () {
        expect(
          formatReleaseDisplay(showAllReleaseSentinel, totalCount: 23),
          equals('\u2193 Show all 23 releases...'),
        );
      });
    });

    group('formatReleaseDate', () {
      test('formats date correctly', () {
        expect(formatReleaseDate(DateTime(2025, 1, 5)), equals('Jan 5'));
        expect(
          formatReleaseDate(DateTime(2025, 12, 31)),
          equals('Dec 31'),
        );
      });
    });
  });
}
