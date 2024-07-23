// ignore_for_file: prefer_const_constructors

import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(ReleasePatch, () {
    test('is equatable', () {
      expect(
        ReleasePatch(
          id: 0,
          number: 1,
          channel: 'channel',
          isRolledBack: false,
          artifacts: const [],
        ),
        equals(
          ReleasePatch(
            id: 0,
            number: 1,
            channel: 'channel',
            isRolledBack: false,
            artifacts: const [],
          ),
        ),
      );
    });
  });
}
