import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/api_exception.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/run_artifact_kind.dart';

/// {@template create_run_artifact}
/// A file a run made, declared so the server can offer its upload.
/// {@endtemplate}
@immutable
class CreateRunArtifact {
  /// {@macro create_run_artifact}
  CreateRunArtifact({
    required this.kind,
    required this.sizeBytes,
  }) {
    sizeBytes.validate(min: 1);
  }

  /// Converts a `Map<String, dynamic>` to a [CreateRunArtifact].
  factory CreateRunArtifact.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'CreateRunArtifact',
      json,
      () => CreateRunArtifact(
        kind: RunArtifactKind.fromJson(json['kind'] as String),
        sizeBytes: json['size_bytes'] as int,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static CreateRunArtifact? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return CreateRunArtifact.fromJson(json);
  }

  /// What a file a run shared is. Each kind has its own rule for when
  /// the customer has agreed to share it.
  final RunArtifactKind kind;

  /// The file's size in bytes, which its upload is held to. Each kind
  /// has its own cap: a `debug_bundle` is at most 1073741824 (1 GiB).
  final int sizeBytes;

  /// Converts a [CreateRunArtifact] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'kind': kind.toJson(),
      'size_bytes': sizeBytes,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    kind,
    sizeBytes,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CreateRunArtifact &&
        kind == other.kind &&
        sizeBytes == other.sizeBytes;
  }
}
