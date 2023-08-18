import 'package:checked_yaml/checked_yaml.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:test/test.dart';

void main() {
  group('ShorebirdYaml', () {
    test('can be deserialized without flavors', () {
      const yaml = '''
app_id: test_app_id
base_url: https://example.com
''';
      final shorebirdYaml = checkedYamlDecode(
        yaml,
        (m) => ShorebirdYaml.fromJson(m!),
      );
      expect(shorebirdYaml.appId, 'test_app_id');
      expect(shorebirdYaml.flavors, isNull);
      expect(shorebirdYaml.baseUrl, 'https://example.com');
    });

    test('can be deserialized with flavors', () {
      const yaml = '''
app_id: test_app_id1
flavors:
  development: test_app_id1
  production: test_app_id2
base_url: https://example.com
''';
      final shorebirdYaml = checkedYamlDecode(
        yaml,
        (m) => ShorebirdYaml.fromJson(m!),
      );
      expect(shorebirdYaml.appId, equals('test_app_id1'));
      expect(shorebirdYaml.flavors, {
        'development': 'test_app_id1',
        'production': 'test_app_id2',
      });
      expect(shorebirdYaml.baseUrl, 'https://example.com');
    });

    test('can be deserialized without auto-update', () {
      const yaml = '''
app_id: test_app_id
''';
      final shorebirdYaml = checkedYamlDecode(
        yaml,
        (m) => ShorebirdYaml.fromJson(m!),
      );
      expect(shorebirdYaml.appId, 'test_app_id');
      expect(shorebirdYaml.flavors, isNull);
      expect(shorebirdYaml.baseUrl, isNull);
      expect(shorebirdYaml.autoUpdate, isNull);
    });

    test('can be deserialized with auto-update', () {
      const yaml = '''
app_id: test_app_id
auto_update: true
''';
      final shorebirdYaml = checkedYamlDecode(
        yaml,
        (m) => ShorebirdYaml.fromJson(m!),
      );
      expect(shorebirdYaml.appId, 'test_app_id');
      expect(shorebirdYaml.flavors, isNull);
      expect(shorebirdYaml.baseUrl, isNull);
      expect(shorebirdYaml.autoUpdate, isTrue);
    });
  });
}
