import 'package:shorebird_code_push/src/shorebird_code_push_base.dart';

/// {@template shorebird_code_push_noop}
/// A no-op implementation of [ShorebirdCodePushBase].
///
/// This is used when the build does not contain the Shorebird Engine.
/// {@endtemplate}
class ShorebirdCodePushNoop implements ShorebirdCodePushBase {
  /// {@macro shorebird_code_push_noop}
  ShorebirdCodePushNoop() {
    // ignore: avoid_print
    print('''
[ShorebirdCodePush]: Shorebird Engine not available, using no-op implementation.
This occurs when using package:shorebird_code_push in an app that does not
contain the Shorebird Engine. Most commonly this is due to building with
`flutter build` or `flutter run` instead of `shorebird release`.
''');
  }
  @override
  Future<int?> currentPatchNumber() async => null;

  @override
  Future<void> downloadUpdateIfAvailable() async {}

  @override
  Future<bool> isNewPatchAvailableForDownload() async => false;

  @override
  Future<bool> isNewPatchReadyToInstall() async => false;

  @override
  bool isShorebirdAvailable() => false;

  @override
  Future<int?> nextPatchNumber() async => null;
}
