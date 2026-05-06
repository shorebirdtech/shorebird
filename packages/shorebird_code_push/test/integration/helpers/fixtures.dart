import 'dart:typed_data';

/// A precomputed bidiff patch artifact along with its hash, mirroring
/// the `PatchFixture` constants in `library/src/c_api/mod.rs`. The
/// bytes were generated with:
///
///     cargo run --bin string_patch -- "<base>" "<new>"
///
/// They are self-contained zstd payloads — applying them against an
/// empty source produces the `new` content, so tests using the stub
/// `FileCallbacks` from `shorebird_test_init` (which read 0 bytes
/// from the source apk) still get the right inflated bytes.
class PatchFixture {
  PatchFixture({
    required this.number,
    required this.base,
    required this.newContent,
    required this.hash,
    required this.bytes,
  });

  final int number;

  /// The libapp bytes the patch was generated against. The integration
  /// harness writes these to `libapp_path` before init — on non-test
  /// desktop builds, `patch_base` reads that file directly when
  /// applying the patch.
  final Uint8List base;

  final String newContent;
  final String hash;
  final Uint8List bytes;
}

/// `string_patch "hello world" "hello tests"`.
final helloTestsPatch = PatchFixture(
  number: 1,
  base: Uint8List.fromList('hello world'.codeUnits),
  newContent: 'hello tests',
  hash: 'bb8f1d041a5cdc259055afe9617136799543e0a7a86f86db82f8c1fadbd8cc45',
  bytes: Uint8List.fromList(const [
    40,
    181,
    47,
    253,
    0,
    128,
    177,
    0,
    0,
    223,
    177,
    0,
    0,
    0,
    16,
    0,
    0,
    6,
    0,
    0,
    0,
    0,
    0,
    0,
    5,
    116,
    101,
    115,
    116,
    115,
    0,
  ]),
);
