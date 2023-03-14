import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'patch.g.dart';

/// {@template patch}
/// A single patch which contains zero or more artifacts.
/// {@endtemplate}
@JsonSerializable()
class Patch {
  /// {@macro patch}
  const Patch({
    required this.number,
    this.artifacts = const [],
    this.channels = const [],
  });

  /// Converts a Map<String, dynamic> to a [Patch]
  factory Patch.fromJson(Map<String, dynamic> json) => _$PatchFromJson(json);

  /// Converts a [Patch] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$PatchToJson(this);

  /// The patch number (newer patches are larger).
  final int number;

  /// The list of channels associated with this patch.
  final List<String> channels;

  /// List of artifacts associated with this patch.
  final List<Artifact> artifacts;
}
