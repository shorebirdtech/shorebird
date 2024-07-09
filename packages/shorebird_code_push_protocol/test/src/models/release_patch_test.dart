import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePatch, () {
    test('is equatable', () {
      expect(
        const ReleasePatch(
          id: 0,
          number: 1,
          channel: 'channel',
          artifacts: [],
        ),
        equals(
          const ReleasePatch(
            id: 0,
            number: 1,
            channel: 'channel',
            artifacts: [],
          ),
        ),
      );
    });
  });
}
