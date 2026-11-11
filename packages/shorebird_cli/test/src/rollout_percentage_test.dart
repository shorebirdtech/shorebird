import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  group('parseRolloutPercentage', () {
    double? parse(String value) =>
        parseRolloutPercentage(value, argName: 'rollout').percentage;

    for (final (value, expected) in [
      ('10', 10.0),
      ('100', 100.0),
      ('0.01', 0.01),
      ('.5', 0.5),
      ('12.5', 12.5),
      ('99.99', 99.99),
      ('10%', 10.0),
      (' 25 ', 25.0),
    ]) {
      test('accepts "$value"', () {
        expect(parse(value), equals(expected));
      });
    }

    for (final value in [
      '0',
      '0.00',
      '100.01',
      '250',
      '-1',
      '1.234',
      '1e2',
      'ten',
      '10.',
      '%',
      '',
    ]) {
      test('rejects "$value" naming the flag', () {
        final (:percentage, :error) = parseRolloutPercentage(
          value,
          argName: 'percentage',
        );
        expect(percentage, isNull);
        expect(
          error,
          equals(
            '--percentage must be a percentage greater than 0 and at most '
            '100, with at most two decimal places, such as 10 or 0.5 '
            '(got "$value").',
          ),
        );
      });
    }
  });

  group('formatRolloutPercentage', () {
    test('drops a trailing .0', () {
      expect(formatRolloutPercentage(10), equals('10%'));
      expect(formatRolloutPercentage(100), equals('100%'));
    });

    test('keeps the decimals that matter', () {
      expect(formatRolloutPercentage(12.5), equals('12.5%'));
      expect(formatRolloutPercentage(0.01), equals('0.01%'));
      expect(formatRolloutPercentage(33.33), equals('33.33%'));
    });
  });

  group('raiseRolloutCommand', () {
    test('has a placeholder without a percentage', () {
      expect(
        raiseRolloutCommand(releaseVersion: '1.0.0+1', patchNumber: 2),
        equals(
          'shorebird patches rollout --release-version 1.0.0+1 '
          '--patch-number 2 --percentage <percentage>',
        ),
      );
    });

    test('passes the app id, flavor and percentage through', () {
      expect(
        raiseRolloutCommand(
          releaseVersion: '1.0.0+1',
          patchNumber: 2,
          percentage: 12.5,
          appId: 'app-id',
          flavor: 'internal',
        ),
        equals(
          'shorebird patches rollout --release-version 1.0.0+1 '
          '--patch-number 2 --app-id app-id --flavor internal '
          '--percentage 12.5',
        ),
      );
    });
  });

  test('rolloutHelp names the subject and the raise command', () {
    expect(rolloutHelp('the patch'), contains('to offer the patch to'));
    expect(rolloutHelp('the patch'), contains('shorebird patches rollout'));
  });
}
