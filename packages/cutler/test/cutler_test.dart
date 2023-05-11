import 'dart:io';

import 'package:cutler/config.dart';
import 'package:cutler/versions.dart';
import 'package:test/test.dart';

void main() {
  test('parseBuildRoot', () {
    final depsContents = File('test/fixtures/DEPS').readAsStringSync();
    final buildrootVersion = parseBuildRoot(depsContents);
    expect(buildrootVersion, 'd6c410f19de5947de40ce110c1e768c887870072');
  });
  test('expandUser', () {
    final path = expandUser('~/foo/bar', env: {'HOME': '/home/user'});
    expect(path, endsWith('/home/user/foo/bar'));
  });
}
