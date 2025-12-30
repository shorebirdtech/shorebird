import 'package:shorebird_cli/src/platform/apple/invalid_export_options_plist_exception.dart';
import 'package:test/test.dart';

void main() {
  group(InvalidExportOptionsPlistException, () {
    test('toString', () {
      final exception = InvalidExportOptionsPlistException('message');
      expect(exception.toString(), 'message');
    });
  });
}
