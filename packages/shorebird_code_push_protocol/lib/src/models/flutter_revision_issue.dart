import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';
import 'package:shorebird_code_push_protocol/src/models/release_platform.dart';

/// {@template flutter_revision_issue}
/// A known problem with the Flutter revision a release was built on,
/// which Shorebird marked bad. Absent from a release whose revision has
/// no mark. A mark names the platforms it affects; a release on none of
/// them is not affected.
/// {@endtemplate}
@immutable
class FlutterRevisionIssue {
  /// {@macro flutter_revision_issue}
  const FlutterRevisionIssue({
    required this.summary,
    this.details,
    this.platforms,
    this.fixedInRevision,
    this.fixedInVersion,
  });

  /// Converts a `Map<String, dynamic>` to a [FlutterRevisionIssue].
  factory FlutterRevisionIssue.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'FlutterRevisionIssue',
      json,
      () => FlutterRevisionIssue(
        summary: json['summary'] as String,
        details: json['details'] as String?,
        platforms: (json['platforms'] as List?)
            ?.map<ReleasePlatform>((e) => ReleasePlatform.fromJson(e as String))
            .toList(),
        fixedInRevision: json['fixed_in_revision'] as String?,
        fixedInVersion: json['fixed_in_version'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static FlutterRevisionIssue? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return FlutterRevisionIssue.fromJson(json);
  }

  /// What is wrong, in one line of at most 80 characters.
  final String summary;

  /// The full explanation and what to do, as markdown.
  final String? details;

  /// The platforms the problem affects. Absent when it affects every
  /// platform.
  final List<ReleasePlatform>? platforms;

  /// The Flutter revision to release with instead, if any.
  final String? fixedInRevision;

  /// The Flutter version of `fixed_in_revision`, when known.
  final String? fixedInVersion;

  /// Converts a [FlutterRevisionIssue] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'summary': summary,
      'details': ?details,
      'platforms': ?platforms?.map((e) => e.toJson()).toList(),
      'fixed_in_revision': ?fixedInRevision,
      'fixed_in_version': ?fixedInVersion,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    summary,
    details,
    listHash(platforms),
    fixedInRevision,
    fixedInVersion,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FlutterRevisionIssue &&
        summary == other.summary &&
        details == other.details &&
        listsEqual(platforms, other.platforms) &&
        fixedInRevision == other.fixedInRevision &&
        fixedInVersion == other.fixedInVersion;
  }
}
