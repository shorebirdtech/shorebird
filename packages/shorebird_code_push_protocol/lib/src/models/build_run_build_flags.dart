import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/model_helpers.dart';

/// {@template build_run_build_flags}
/// The flags a run built with that change compiled Dart code, as
/// SHA-256 hashes. Never holds dart-define values or paths.
/// {@endtemplate}
@immutable
class BuildRunBuildFlags {
  /// {@macro build_run_build_flags}
  const BuildRunBuildFlags({
    required this.dartDefineCount,
    required this.dartDefines,
    this.target,
  });

  /// Converts a `Map<String, dynamic>` to a [BuildRunBuildFlags].
  factory BuildRunBuildFlags.fromJson(Map<String, dynamic> json) {
    return parseFromJson(
      'BuildRunBuildFlags',
      json,
      () => BuildRunBuildFlags(
        dartDefineCount: json['dart_define_count'] as int,
        dartDefines: (json['dart_defines'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, value as String),
        ),
        target: json['target'] as String?,
      ),
    );
  }

  /// Convenience to create a nullable type from a nullable json object.
  /// Useful when parsing optional fields.
  static BuildRunBuildFlags? maybeFromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }
    return BuildRunBuildFlags.fromJson(json);
  }

  /// How many --dart-define values the build used.
  final int dartDefineCount;

  /// Each dart-define key with the hex SHA-256 of its value.
  final Map<String, String> dartDefines;

  /// The hex SHA-256 of the --target path relative to the project,
  /// absent for the default entrypoint.
  final String? target;

  /// Converts a [BuildRunBuildFlags] to a `Map<String, dynamic>`.
  Map<String, dynamic> toJson() {
    return {
      'dart_define_count': dartDefineCount,
      'dart_defines': dartDefines,
      'target': ?target,
    };
  }

  @override
  int get hashCode => Object.hashAll([
    dartDefineCount,
    mapHash(dartDefines),
    target,
  ]);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BuildRunBuildFlags &&
        dartDefineCount == other.dartDefineCount &&
        mapsEqual(dartDefines, other.dartDefines) &&
        target == other.target;
  }
}
