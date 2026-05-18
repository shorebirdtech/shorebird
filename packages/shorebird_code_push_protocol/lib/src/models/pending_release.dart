import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template pending_release}
/// A newer release that has been created but not yet analyzed.
/// Surfaced alongside the most recent analyzed release so clients
/// can show an "analyzing…" indicator without losing the stable
/// icon and metadata.
/// {@endtemplate}
@immutable
class PendingRelease {
  /// {@macro pending_release}
  const PendingRelease({
    required this.id,
    required this.version,
    required this.createdAt,
  });

  /// Converts a `Map<String, dynamic>` to a [PendingRelease].
  factory PendingRelease.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'PendingRelease',
      json,
      () => PendingRelease(
        id: json['id'] as int,
        version: json['version'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static PendingRelease? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return PendingRelease.fromJson(json);
  }

  /// The ID of the pending release.
  final int id;

  /// The version of the pending release.
  final String version;

  /// The date and time the pending release was created.
  final DateTime createdAt;

  /// Converts a [PendingRelease] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'created_at': createdAt.toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    version,
    createdAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingRelease &&
        id == other.id &&
        version == other.version &&
        createdAt == other.createdAt;
  }
}
