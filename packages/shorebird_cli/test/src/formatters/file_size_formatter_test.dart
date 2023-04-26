import 'dart:math';

import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:test/test.dart';

void main() {
  group('formatBytes', () {
    test('returns 0B for anything less than 0', () {
      expect(formatBytes(-1), equals('0 B'));
      expect(formatBytes(-100), equals('0 B'));
    });

    test('returns 0B for 0', () {
      expect(formatBytes(0), equals('0 B'));
    });

    test('returns 1KB for 1024 bytes', () {
      expect(formatBytes(1024), equals('1 KB'));
    });

    test('returns 1MB for 1024 kilobytes', () {
      expect(formatBytes(pow(1024, 2).floor()), equals('1 MB'));
    });

    test('returns 1GB for 1024 megabytes', () {
      expect(formatBytes(pow(1024, 3).floor()), equals('1 GB'));
    });

    test('returns 1TB for 1024 gigabytes', () {
      expect(formatBytes(pow(1024, 4).floor()), equals('1 TB'));
    });

    test('returns 1PB for 1024 terabytes', () {
      expect(formatBytes(pow(1024, 5).floor()), equals('1 PB'));
    });

    test('returns 1EB for 1024 petabytes', () {
      expect(formatBytes(pow(1024, 6).floor()), equals('1 EB'));
    });

    test('returns correct number of decimal places', () {
      expect(formatBytes(1524, decimals: 0), equals('1 KB'));
      expect(formatBytes(1524, decimals: 1), equals('1.5 KB'));
      // ignore: avoid_redundant_argument_values
      expect(formatBytes(1524, decimals: 2), equals('1.49 KB'));
      expect(formatBytes(1524, decimals: 3), equals('1.488 KB'));
    });
  });
}
