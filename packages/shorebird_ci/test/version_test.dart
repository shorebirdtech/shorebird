import 'dart:io';

import 'package:shorebird_ci/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(packageVersion, pubspec['version']);
  });
}
