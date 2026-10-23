import 'package:shorebird_cli/src/patch_verification.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  useTempWorkingDirectory();

  // The engine of Flutter 3.41.9, the first whose install_only skips the
  // signature check.
  const brokenEngineRevision = '6eae37c3bd60906cfaa3b026b3271b896a76e46f';
  // The engine of Flutter 3.41.8, the last before it.
  const goodEngineRevision = '145c457f310dc800caa96f163cfde167df18f0da';

  group('installOnlyBrokenEngineRevisions', () {
    test('holds the engine of every affected release', () {
      // The engines of the flutter_release/3.41.9, 3.44.0-3.44.9 and
      // 3.47.0-3.47.7 heads, the shipped builds most releases use.
      const releaseEngines = <String>[
        '6eae37c3bd60906cfaa3b026b3271b896a76e46f', // 3.41.9
        '6500c84eba818b598fb967bd0276e6e50cdd02c9', // 3.44.0
        'caf48e58a872271fc47e43f7dae6192bb78d60d1', // 3.44.1
        '45755df581369c86e6d793576b11dc5560d783cf', // 3.44.2
        'a47823d9ce1d614a3de214b8b88eb3025e6e8256', // 3.44.4
        'e8627aad0813f11af5b42d1cb3e168121bf5d240', // 3.44.3
        '3a6bc396ffd240815fe9c1f3e55a6b59486c1699', // 3.44.5
        '401254d5890cba1abe1ea364004f4d6bf8e58c24', // 3.44.6
        '69f9831c360d9152862ec3897c67fb09ae843f3b', // 3.44.8
        'e1eaecbcac6d9a32cb5590c646e21cf21252cf19', // 3.44.7
        '27bc060323bfdfe2f5b6732174d4e499e74eca70', // 3.44.9
        '5a91274d10582c35d6df695511e327879664e35c', // 3.47.0
        '03e67977a7ff5893d96ac97f22c6a795530c0040', // 3.47.1
        '315ff242617023c1c5549878bf17fad51ffec6f3', // 3.47.2
        'a9314be8d17d13dec4a707dc092e1cc1a65abbde', // 3.47.3
        '2c6e13f6780942303fce2dad4d571893f8e81f97', // 3.47.4
        'c663a2682e6adfc60a1aaff99ff62baa891dcf87', // 3.47.5
        '124e4abb1ed0107b1fad97d64e7353f13c8b1198', // 3.47.6
        '9e6800c5ce7addd79a287b1be563a42838f1d351', // 3.47.7
      ];
      expect(installOnlyBrokenEngineRevisions, containsAll(releaseEngines));
    });

    test('holds only full engine revisions', () {
      for (final revision in installOnlyBrokenEngineRevisions) {
        expect(revision, matches(RegExp(r'^[0-9a-f]{40}$')));
      }
    });
  });

  group(installOnlySkipsSignatureCheck, () {
    test('is true for an engine with the bug', () {
      expect(installOnlySkipsSignatureCheck(brokenEngineRevision), isTrue);
    });

    test('is false for other engines', () {
      expect(installOnlySkipsSignatureCheck(goodEngineRevision), isFalse);
    });
  });
}
