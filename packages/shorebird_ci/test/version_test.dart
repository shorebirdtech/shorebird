import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:shorebird_ci/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  // Found from the package URI, not Directory.current: other suites
  // change the current directory, and it is shared by every isolate
  // in the test process.
  late String packageRoot;

  setUpAll(() async {
    final library = await Isolate.resolvePackageUri(
      Uri.parse('package:shorebird_ci/shorebird_ci.dart'),
    );
    packageRoot = p.dirname(p.dirname(library!.toFilePath()));
  });

  test('packageVersion matches pubspec.yaml', () {
    final pubspec =
        loadYaml(
              File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync(),
            )
            as YamlMap;
    expect(packageVersion, pubspec['version']);
  });

  test('example workflow pins packageVersion', () {
    final example = File(
      p.join(packageRoot, 'example', 'shorebird_ci.yaml'),
    ).readAsStringSync();
    expect(
      example,
      contains('dart pub global activate shorebird_ci $packageVersion\n'),
    );
  });
}
