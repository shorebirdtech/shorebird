/// The version of this package, kept equal to `version:` in
/// `pubspec.yaml` (test/version_test.dart checks it).
///
/// `generate` pins `dart pub global activate shorebird_ci` to this
/// version, so a workflow keeps running the shorebird_ci that wrote it
/// until it is regenerated, rather than whatever was published last.
const packageVersion = '0.2.5';
