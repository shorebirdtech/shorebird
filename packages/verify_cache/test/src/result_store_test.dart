import 'package:test/test.dart';
import 'package:verify_cache/verify_cache.dart';

import 'helpers.dart';

void main() {
  group(ResultStore, () {
    test('has no entry for an unrecorded digest', () {
      expect(ResultStore(tempDir()).lookup('abc'), isNull);
    });

    test('returns what was recorded, and leaves nothing else', () {
      final dir = tempDir();
      final store = ResultStore(dir)..record('abc', 'entry');
      expect(store.lookup('abc'), 'entry');
      expect(
        dir.listSync(recursive: true).map((e) => e.path.split('/').last),
        unorderedEquals(['passed', 'abc']),
      );
    });

    test('a second record replaces the first', () {
      final store = ResultStore(tempDir())
        ..record('abc', 'first')
        ..record('abc', 'second');
      expect(store.lookup('abc'), 'second');
    });
  });
}
