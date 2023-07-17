import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleaseStatus, () {
    test('named allows lookup based on name', () {
      expect(ReleaseStatus.named('draft'), equals(ReleaseStatus.draft));
      expect(ReleaseStatus.named('active'), equals(ReleaseStatus.active));
    });
  });
}
