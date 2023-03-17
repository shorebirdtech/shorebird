import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('Patch', () {
    test('can be (de)serialized', () {
      const patch = Patch(id: 1, number: 2);
      expect(
        Patch.fromJson(patch.toJson()).toJson(),
        equals(patch.toJson()),
      );
    });
  });
}
