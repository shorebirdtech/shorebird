import 'package:cli_io/cli_io.dart';
import 'package:test/test.dart';

void main() {
  group('Level', () {
    test('orders from most verbose to least', () {
      expect(Level.verbose.index, lessThan(Level.debug.index));
      expect(Level.debug.index, lessThan(Level.info.index));
      expect(Level.info.index, lessThan(Level.warning.index));
      expect(Level.warning.index, lessThan(Level.error.index));
      expect(Level.error.index, lessThan(Level.critical.index));
      expect(Level.critical.index, lessThan(Level.quiet.index));
    });
  });
}
