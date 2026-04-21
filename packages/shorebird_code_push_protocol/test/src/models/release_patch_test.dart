import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePatch, () {
    test('is equatable', () {
      expect(
        // Ignoring const constructor for equality comparison.
        const ReleasePatch(
          id: 0,
          number: 1,
          channel: 'channel',
          isRolledBack: false,
          artifacts: [],
        ),
        equals(
          // Ignoring const constructor for equality comparison.
          const ReleasePatch(
            id: 0,
            number: 1,
            channel: 'channel',
            isRolledBack: false,
            artifacts: [],
          ),
        ),
      );
    });
  });
}
