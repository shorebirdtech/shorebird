import 'package:shorebird_cli/src/commands/patch_new/android_patcher.dart';
import 'package:test/test.dart';

void main() {
  group(AndroidPatcher, () {
    late AndroidPatcher patcher;

    setUp(() {
      patcher = AndroidPatcher(flavor: null, target: null);
    });
  });
}
