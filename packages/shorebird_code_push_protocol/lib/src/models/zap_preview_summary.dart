import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template zap_preview_summary}
/// A preview as it appears in a list.
/// {@endtemplate}
@immutable
class ZapPreviewSummary {
  /// {@macro zap_preview_summary}
  const ZapPreviewSummary({
    required this.id,
    required this.name,
    required this.build,
    required this.updatedAt,
    required this.expiresAt,
  });

  /// Converts a `Map<String, dynamic>` to a [ZapPreviewSummary].
  factory ZapPreviewSummary.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'ZapPreviewSummary',
      json,
      () => ZapPreviewSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        build: checkedKey(json, 'build') as String?,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static ZapPreviewSummary? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return ZapPreviewSummary.fromJson(json);
  }

  /// The ID of the preview.
  final String id;

  /// The preview's display name. `Untitled` when none was given.
  final String name;

  /// The ID of the preview's latest published build, or null when
  /// nothing has been published to it yet.
  final String? build;

  /// When the preview was last changed.
  final DateTime updatedAt;

  /// When the preview stops being served. Publishing a build pushes it
  /// out to 7 days from the publish.
  final DateTime expiresAt;

  /// Converts a [ZapPreviewSummary] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'build': build,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    name,
    build,
    updatedAt,
    expiresAt,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ZapPreviewSummary &&
        id == other.id &&
        name == other.name &&
        build == other.build &&
        updatedAt == other.updatedAt &&
        expiresAt == other.expiresAt;
  }
}
