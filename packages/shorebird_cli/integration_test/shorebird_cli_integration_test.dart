import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

void main() {
  group('integration tests', () {
    test('checks for version', () async {
      final result = await Process.run(
        'shorebird',
        ['--version'],
        runInShell: true,
      );
      expect(result.stderr, isEmpty);
      expect(
        result.stdout,
        stringContainsInOrder(['Shorebird Engine', 'revision']),
      );
      expect(result.exitCode, 0);
    });
  });
}
