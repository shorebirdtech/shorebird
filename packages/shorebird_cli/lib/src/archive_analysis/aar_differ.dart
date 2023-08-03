import 'package:shorebird_cli/src/archive_analysis/android_archive_differ.dart';

/// Finds differences between two AABs.
///
/// Types of changes we care about:
///   - Dart code changes
///      - libapp.so will be different
///   - Assets
///      - **/assets/** will be different
///      - AssetManifest.json will have changed if assets have been added or
///        removed
///
/// See
/// https://developer.android.com/studio/projects/android-library.html#aar-contents
/// for reference. Note that .aars produced by Flutter modules do not contain
/// .jar files, so only asset and dart changes are possible.
class AarDiffer extends AndroidArchiveDiffer {}
