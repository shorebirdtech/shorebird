import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:test/test.dart';

import '../override_print.dart';

void main() {
  group(ShorebirdUpdater, () {
    test(
      'can be instantiated',
      overridePrint((_) {
        expect(ShorebirdUpdater.new, returnsNormally);
      }),
    );
  });
}
