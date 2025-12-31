import 'package:meta/meta.dart';

/// A record containing the exit code and optionally link percentage
/// returned by `runLinker`.
@immutable
class LinkResult {
  /// Creates a new [LinkResult] representing failure.
  const LinkResult.failure()
    : exitCode = 70,
      linkPercentage = null,
      linkMetadata = null;

  /// Creates a new [LinkResult] representing success.
  const LinkResult.success({required this.linkPercentage, this.linkMetadata})
    : exitCode = 0;

  /// The exit code of the linker process.
  final int exitCode;

  /// The percentage of code that was linked in the patch.
  final double? linkPercentage;

  /// Metadata from the linker, if available.
  final Map<String, dynamic>? linkMetadata;
}
