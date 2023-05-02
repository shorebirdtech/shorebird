import 'package:checked_yaml/checked_yaml.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:test/test.dart';

void main() {
  group('ShorebirdYaml', () {
    test('can be deserialized with single app_id', () {
      const yaml = '''
app_id: test_app_id
base_url: https://example.com
''';
      final shorebirdYaml = checkedYamlDecode(
        yaml,
        (m) => ShorebirdYaml.fromJson(m!),
      );
      expect(shorebirdYaml.appId.value, 'test_app_id');
      expect(shorebirdYaml.appId.values, isNull);
      expect(shorebirdYaml.baseUrl, 'https://example.com');
    });

    test('can be deserialized with multiple app_id', () {
      const yaml = '''
app_id:
  development: test_app_id1
  production: test_app_id2
base_url: https://example.com
''';
      final shorebirdYaml = checkedYamlDecode(
        yaml,
        (m) => ShorebirdYaml.fromJson(m!),
      );
      expect(shorebirdYaml.appId.value, isNull);
      expect(shorebirdYaml.appId.values, {
        'development': 'test_app_id1',
        'production': 'test_app_id2',
      });
      expect(shorebirdYaml.baseUrl, 'https://example.com');
    });
  });
}
