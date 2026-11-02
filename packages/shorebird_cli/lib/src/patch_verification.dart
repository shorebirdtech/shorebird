/// Shorebird engine revisions whose updater never checks the patch signature
/// when `patch_verification: install_only` is set.
///
/// The bug came in with updater#352 (engine bumped 2026-05-07, Flutter
/// 3.41.9) and is in every engine built since, up to the updater fix. This
/// list is closed: it holds every engine revision we shipped with the bug
/// (the heads of flutter_release/3.41.9, 3.44.0-3.44.9 and 3.47.0-3.47.7,
/// earlier builds of those branches, and shorebird/dev builds the CLI
/// pinned), and every engine built after the fix is fixed. A fixed rebuild
/// of any of these versions gets a new engine revision, so it isn't on this
/// list and needs no CLI change.
///
/// Keyed on the engine revision rather than the Flutter revision: every
/// Flutter revision that uses one of these engines carries the bug,
/// including ones no release branch points at.
///
/// Strict mode (verify at every launch) is unaffected on these engines.
const installOnlyBrokenEngineRevisions = <String>{
  '6eae37c3bd60906cfaa3b026b3271b896a76e46f', // 3.41.9, 2026-05-07
  '3a51c41c239ee82fc57e684b8c277863b7a78c6c', // 2026-05-11
  'bfbecc518f82717f87f2f2f1cee94c7d04eb1354', // 2026-05-14
  'e838fe1c30a47ae7770d64cce15944cc2fa2c408', // 2026-05-16
  'f3c6261179a824f40716038bc3491e2a4af9f195', // 2026-05-20
  'da3fb113912132a7170aa6323076679e82b7a1ec', // 2026-05-21
  '6500c84eba818b598fb967bd0276e6e50cdd02c9', // 3.44.0, 2026-05-22
  'ef5e9b9e1d78eebd4c4b531c429ebd6981271748', // 2026-06-01
  'b6eef3b930179c4a408f8e3c7f9c30feb4227b73', // 2026-06-04
  'caf48e58a872271fc47e43f7dae6192bb78d60d1', // 3.44.1, 2026-06-04
  '45755df581369c86e6d793576b11dc5560d783cf', // 3.44.2, 2026-06-11
  'a47823d9ce1d614a3de214b8b88eb3025e6e8256', // 3.44.4, 2026-06-22
  'e8627aad0813f11af5b42d1cb3e168121bf5d240', // 3.44.3, 2026-06-22
  '3a6bc396ffd240815fe9c1f3e55a6b59486c1699', // 3.44.5, 2026-07-06
  '401254d5890cba1abe1ea364004f4d6bf8e58c24', // 3.44.6, 2026-07-06
  '69f9831c360d9152862ec3897c67fb09ae843f3b', // 3.44.8, 2026-07-06
  'a787a8fe98e99918255bb4bf4835f6ae010c1035', // 2026-07-06
  'e1eaecbcac6d9a32cb5590c646e21cf21252cf19', // 3.44.7, 2026-07-06
  '27bc060323bfdfe2f5b6732174d4e499e74eca70', // 3.44.9, 2026-08-14
  'e3a33a5c417acb5db9a9d8c0d963d11bdd074205', // 2026-08-14
  '5a91274d10582c35d6df695511e327879664e35c', // 3.47.0, 2026-08-17
  '03e67977a7ff5893d96ac97f22c6a795530c0040', // 3.47.1, 2026-08-21
  '315ff242617023c1c5549878bf17fad51ffec6f3', // 3.47.2, 2026-08-28
  '65e9873c5346d31ea274ad9de55ede09d6c4bc51', // 2026-09-14
  'a9314be8d17d13dec4a707dc092e1cc1a65abbde', // 3.47.3, 2026-09-14
  '2c6e13f6780942303fce2dad4d571893f8e81f97', // 3.47.4, 2026-09-16
  'c663a2682e6adfc60a1aaff99ff62baa891dcf87', // 3.47.5, 2026-09-21
  '124e4abb1ed0107b1fad97d64e7353f13c8b1198', // 3.47.6, 2026-10-02
  '1a6158332f5490c3fd6087394b6f3376c818fa7b', // 2026-10-09
  '4b936a0c03e13389ddfb1ac48823f187964975c2', // 2026-10-09
  '9e6800c5ce7addd79a287b1be563a42838f1d351', // 3.47.7, 2026-10-22
};

/// Whether `patch_verification: install_only` skips the patch signature
/// check on [engineRevision].
bool installOnlySkipsSignatureCheck(String engineRevision) =>
    installOnlyBrokenEngineRevisions.contains(engineRevision);
