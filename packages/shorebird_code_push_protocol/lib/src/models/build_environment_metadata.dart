import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'build_environment_metadata.g.dart';

/// {@template build_environment_metadata}
/// Information about the environment used to build a release or patch.
/// {@endtemplate}
@JsonSerializable()
class BuildEnvironmentMetadata extends Equatable {
  /// {@macro build_environment_metadata}
  const BuildEnvironmentMetadata({
    required this.shorebirdVersion,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.xcodeVersion,
  });

  /// coverage:ignore-start
  /// Creates a [BuildEnvironmentMetadata] with overridable default values for
  /// testing purposes.
  factory BuildEnvironmentMetadata.forTest({
    String shorebirdVersion = '4.5.6',
    String operatingSystem = 'macos',
    String operatingSystemVersion = '1.2.3',
    String? xcodeVersion = '15.0',
  }) =>
      BuildEnvironmentMetadata(
        shorebirdVersion: shorebirdVersion,
        operatingSystem: operatingSystem,
        operatingSystemVersion: operatingSystemVersion,
        xcodeVersion: xcodeVersion,
      );

  /// Converts a Map<String, dynamic> to a [BuildEnvironmentMetadata]
  factory BuildEnvironmentMetadata.fromJson(Map<String, dynamic> json) =>
      _$BuildEnvironmentMetadataFromJson(json);

  /// Converts a [BuildEnvironmentMetadata] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$BuildEnvironmentMetadataToJson(this);

  /// The version of Shorebird used to run the command.
  final String shorebirdVersion;

  /// The operating system used to run the release command.
  final String operatingSystem;

  /// The version of [operatingSystem].
  final String operatingSystemVersion;

  /// The version of Xcode used to build the patch. Only provided for iOS
  /// patches.
  final String? xcodeVersion;

  @override
  List<Object?> get props => [
        shorebirdVersion,
        operatingSystem,
        operatingSystemVersion,
        xcodeVersion,
      ];
}
