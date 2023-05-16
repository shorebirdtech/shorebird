import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group(App, () {
    test('can be (de)serialized', () {
      const app = App(
        id: '30370f27-dbf1-4673-8b20-fb096e38dffa',
        displayName: 'My App',
      );
      expect(App.fromJson(app.toJson()).toJson(), equals(app.toJson()));
    });
  });
}
