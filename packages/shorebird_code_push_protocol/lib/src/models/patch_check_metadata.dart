import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template patch_check_metadata}
/// Patch metadata representing the contents of a patch for a
/// specific platform and architecture.
/// {@endtemplate}
@immutable
class PatchCheckMetadata {
  /// {@macro patch_check_metadata}
  const PatchCheckMetadata({
    required this.number,
    required this.downloadUrl,
    required this.hash,
    this.hashSignature,
  });

  /// Converts a `Map<String, dynamic>` to a [PatchCheckMetadata].
  factory PatchCheckMetadata.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PatchCheckMetadata',
      json,
      () => PatchCheckMetadata(
        number: json['number'] as int,
        downloadUrl: json['download_url'] as String,
        hash: json['hash'] as String,
        hashSignature: json['hash_signature'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PatchCheckMetadata? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PatchCheckMetadata.fromJson(json);
  }

  /// The patch number associated with the artifact.
  final int number;

  /// The URL of the artifact.
  final String downloadUrl;

  /// The hash of the artifact.
  final String hash;

  /// The signature of the `hash`.
  final String? hashSignature;

  /// Converts a [PatchCheckMetadata] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'download_url': downloadUrl,
      'hash': hash,
      'hash_signature': hashSignature,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    number,
    downloadUrl,
    hash,
    hashSignature,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PatchCheckMetadata &&
        number == other.number &&
        downloadUrl == other.downloadUrl &&
        hash == other.hash &&
        hashSignature == other.hashSignature;
  }
}
