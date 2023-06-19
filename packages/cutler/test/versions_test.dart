import 'dart:io';

import 'package:cutler/versions.dart';
import 'package:test/test.dart';

void main() {
  test('parseBuildrootVersion', () {
    final depsContents = File('test/fixtures/DEPS').readAsStringSync();
    final buildrootHash = parseBuildrootRevision(depsContents);
    expect(buildrootHash, 'd6c410f19de5947de40ce110c1e768c887870072');
  });
  test('parseDartVersion', () {
    final depsContents = File('test/fixtures/DEPS').readAsStringSync();
    final dartHash = parseDartRevision(depsContents);
    expect(dartHash, '7a6514d1377175decd3a886fe4190fbbebddac3a');
  });
}
