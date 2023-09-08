import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'patch_event.g.dart';

/// {@template patch_event}
/// Base class for patch events.
/// {@endtemplate}
@JsonSerializable()
class PatchEvent {
  /// {@macro patch_event}
  const PatchEvent({
    required this.clientId,
    required this.appId,
    required this.releaseVersion,
    required this.patchNumber,
    required this.platform,
    required this.arch,
    required this.identifier,
  });

  /// Converts a Map<String, dynamic> to a [PatchEvent]
  factory PatchEvent.fromJson(Map<String, dynamic> json) =>
      _$PatchEventFromJson(json);

  /// Converts a [PatchEvent] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$PatchEventToJson(this);

  /// The type of patch event.
  @JsonKey(name: 'type')
  final String identifier;

  /// The client id of the device being updated.
  final String clientId;

  /// The id of the app being updated.
  final String appId;

  /// The id of the app being updated.
  final String releaseVersion;

  /// The patch number being installed.
  final int patchNumber;

  /// The platform of the device being updated.
  final ReleasePlatform platform;

  /// The architecture of the device being updated.
  final String arch;
}
