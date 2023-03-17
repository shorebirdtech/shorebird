import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('App', () {
    test('can be (de)serialized', () {
      const app = App(
        appId: 'my_app',
        latestReleaseVersion: '1.0.0',
        latestPatchNumber: 1,
      );
      expect(App.fromJson(app.toJson()).toJson(), equals(app.toJson()));
    });
  });
}
