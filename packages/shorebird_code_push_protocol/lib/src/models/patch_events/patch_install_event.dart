import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

part 'patch_install_event.g.dart';

/// {@template patch_install_event}
/// Event for when a patch is installed.
/// {@endtemplate}
@JsonSerializable()
class PatchInstallEvent extends PatchEvent {
  /// {@macro patch_install_event}
  PatchInstallEvent({
    required this.clientId,
    required this.appId,
    required this.releaseVersion,
    required this.patchNumber,
    required this.platform,
    required this.arch,
    super.type = PatchInstallEvent.identifier,
  });

  /// Converts a Map<String, dynamic> to a [PatchInstallEvent]
  factory PatchInstallEvent.fromJson(Map<String, dynamic> json) =>
      _$PatchInstallEventFromJson(json);

  /// Converts a [PatchInstallEvent] to a Map<String, dynamic>
  @override
  Map<String, dynamic> toJson() => _$PatchInstallEventToJson(this);

  /// The patch install event type identifier.
  static const identifier = '__patch_install__';

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
