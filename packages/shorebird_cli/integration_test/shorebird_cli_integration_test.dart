import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('--version', () async {
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
}
