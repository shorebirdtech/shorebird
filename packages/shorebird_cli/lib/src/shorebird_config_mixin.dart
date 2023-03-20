import 'dart:io';

import 'package:checked_yaml/checked_yaml.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/config/config.dart';
import 'package:yaml/yaml.dart';

mixin ShorebirdConfigMixin on ShorebirdCommand {
  bool get hasShorebirdYaml => getShorebirdYaml() != null;

  bool get hasPubspecYaml => getPubspecYaml() != null;

  bool get isShorebirdInitialized {
    return hasShorebirdYaml && pubspecContainsShorebirdYaml;
  }

  Uri? get hostedUri {
    final baseUrl = getShorebirdYaml()?.baseUrl;
    return baseUrl == null ? null : Uri.tryParse(baseUrl);
  }

  bool get pubspecContainsShorebirdYaml {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    final pubspecContents = file.readAsStringSync();
    final yaml = loadYaml(pubspecContents, sourceUrl: file.uri) as Map;
    if (!yaml.containsKey('flutter')) return false;
    if (!(yaml['flutter'] as Map).containsKey('assets')) return false;
    final assets = (yaml['flutter'] as Map)['assets'] as List;
    return assets.contains('shorebird.yaml');
  }

  ShorebirdYaml? getShorebirdYaml() {
    final file = File(p.join(Directory.current.path, 'shorebird.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return checkedYamlDecode(yaml, (m) => ShorebirdYaml.fromJson(m!));
  }

  Pubspec? getPubspecYaml() {
    final file = File(p.join(Directory.current.path, 'pubspec.yaml'));
    if (!file.existsSync()) return null;
    final yaml = file.readAsStringSync();
    return Pubspec.parse(yaml);
  }
}
