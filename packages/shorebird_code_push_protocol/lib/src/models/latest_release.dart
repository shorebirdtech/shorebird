import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_analysis.dart';
import 'package:shorebird_code_push_protocol/src/models/release_status.dart';

/// {@template latest_release}
/// Per-platform projection of an analyzed release as surfaced by
/// `AppMetadata.latest_releases`. Each entry corresponds to the
/// most recent analyzed release on the keying platform, so
/// `analysis` is always populated and `status` is the single
/// per-platform status (rather than the cross-platform
/// `platform_statuses` map carried by `Release`).
/// {@endtemplate}
@immutable
class LatestRelease {
  /// {@macro latest_release}
  const LatestRelease({
    required this.id,
    required this.version,
    required this.flutterRevision,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required this.analysis,
    this.flutterVersion,
    this.notes,
  });

  /// Converts a `Map<String, dynamic>` to a [LatestRelease].
  factory LatestRelease.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'LatestRelease',
      json,
      () => LatestRelease(
        id: json['id'] as int,
        version: json['version'] as String,
        flutterRevision: json['flutter_revision'] as String,
        flutterVersion: json['flutter_version'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
        status: ReleaseStatus.fromJson(json['status'] as String),
        notes: json['notes'] as String?,
        analysis: ReleaseAnalysis.fromJson(
          json['analysis'] as Map<String, dynamic>,
        ),
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static LatestRelease? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return LatestRelease.fromJson(json);
  }

  /// The ID of the release.
  final int id;

  /// The version of the release.
  final String version;

  /// The Flutter revision used to create the release.
  final String flutterRevision;

  /// The Flutter version used to create the release. Optional
  /// because it was added later; older releases do not have it.
  final String? flutterVersion;

  /// The date and time the release was created.
  final DateTime createdAt;

  /// The date and time the release was last updated.
  final DateTime updatedAt;

  /// The status of a release.
  final ReleaseStatus status;

  /// Freeform notes associated with the release, if any.
  final String? notes;

  /// Analyzer-extracted metadata for a release artifact on a single
  /// platform.
  final ReleaseAnalysis analysis;

  /// Converts a [LatestRelease] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'version': version,
      'flutter_revision': flutterRevision,
      'flutter_version': flutterVersion,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'status': status.toJson(),
      'notes': notes,
      'analysis': analysis.toJson(),
    };
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    version,
    flutterRevision,
    flutterVersion,
    createdAt,
    updatedAt,
    status,
    notes,
    analysis,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LatestRelease &&
        id == other.id &&
        version == other.version &&
        flutterRevision == other.flutterRevision &&
        flutterVersion == other.flutterVersion &&
        createdAt == other.createdAt &&
        updatedAt == other.updatedAt &&
        status == other.status &&
        notes == other.notes &&
        analysis == other.analysis;
  }
}
