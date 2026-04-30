import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Reads and parses `pubspec.yaml` from [packageDir].
///
/// Returns `null` if the file doesn't exist, doesn't parse as YAML, or
/// the top-level value isn't a map (e.g., the file is malformed or
/// has been replaced with a list).
YamlMap? readPubspec(String packageDir) {
  final file = File(p.join(packageDir, 'pubspec.yaml'));
  if (!file.existsSync()) return null;
  try {
    final yaml = loadYaml(file.readAsStringSync());
    return yaml is YamlMap ? yaml : null;
  } on Exception {
    return null;
  }
}
