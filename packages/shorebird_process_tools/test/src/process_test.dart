import 'package:shorebird_process_tools/src/process.dart';
import 'package:test/test.dart';

void main() {
  group(ShorebirdProcessResult, () {
    test('can be instantiated', () {
      const result = ShorebirdProcessResult(
        exitCode: 0,
        stdout: 'stdout',
        stderr: 'stderr',
      );
      expect(result.exitCode, equals(0));
      expect(result.stdout, equals('stdout'));
      expect(result.stderr, equals('stderr'));
    });
  });
}
