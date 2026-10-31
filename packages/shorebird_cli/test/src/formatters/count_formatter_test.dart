import 'package:shorebird_cli/src/formatters/formatters.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  useTempWorkingDirectory();

  group(formatCount, () {
    test('is singular for one', () {
      expect(formatCount(1, 'app'), '1 app');
    });

    test('is plural otherwise', () {
      expect(formatCount(0, 'app'), '0 apps');
      expect(formatCount(3, 'app'), '3 apps');
    });
  });
}
