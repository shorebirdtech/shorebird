import 'package:shorebird_cli/src/third_party/flutter_tools/lib/flutter_tools.dart';
import 'package:test/test.dart';

void main() {
  group(ProcessExit, () {
    test('includes message in string representation', () {
      final exception = ProcessExit(1);
      expect(exception.toString(), 'ProcessExit: 1');
    });
  });
}
