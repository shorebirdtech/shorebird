import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'release.g.dart';

/// {@template release}
/// A single release which contains zero or more patches.
/// {@endtemplate}
@JsonSerializable()
class Release {
  /// {@macro release}
  Release({required this.version, List<Patch>? patches})
      : patches = patches ?? [];

  /// Converts a Map<String, dynamic> to a [Release]
  factory Release.fromJson(Map<String, dynamic> json) =>
      _$ReleaseFromJson(json);

  /// Converts a [Release] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$ReleaseToJson(this);

  /// The version of the release.
  final String version;

  /// List of patches associated with this release.
  final List<Patch> patches;
}
