import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'build_environment_metadata.g.dart';

/// {@template build_environment_metadata}
/// Information about the environment used to build a release or patch.
///
/// Collection of this information is done to help Shorebird users debug any
/// later failures in their builds.
///
/// We do not collect Personally Identifying Information (e.g. no paths,
/// argument lists, etc.) in accordance with our privacy policy:
/// https://shorebird.dev/privacy/
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
  // coverage:ignore-end

  /// Converts a Map<String, dynamic> to a [BuildEnvironmentMetadata]
  factory BuildEnvironmentMetadata.fromJson(Map<String, dynamic> json) =>
      _$BuildEnvironmentMetadataFromJson(json);

  /// Converts a [BuildEnvironmentMetadata] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$BuildEnvironmentMetadataToJson(this);

  /// The version of Shorebird used to run the command.
  ///
  /// Reason: each version of shorebird has new features and bug fixes. Users
  /// using an older version may be running into issues that have already been
  /// fixed.
  final String shorebirdVersion;

  /// The operating system used to run the release command.
  ///
  /// Reason: issues may occur on some OSes and not others (especially Windows
  /// vs non-Windows).
  final String operatingSystem;

  /// The version of [operatingSystem].
  ///
  /// Reason: issues may occur on some OS versions and not others.
  final String operatingSystemVersion;

  /// The version of Xcode used to build the patch. Only provided for iOS
  /// patches.
  ///
  /// Reason: Xcode behavior can change between versions. Ex: the
  /// `shorebird preview` mechanism changed entirely between Xcode 14 and 15.
  final String? xcodeVersion;

  @override
  List<Object?> get props => [
        shorebirdVersion,
        operatingSystem,
        operatingSystemVersion,
        xcodeVersion,
      ];
}
