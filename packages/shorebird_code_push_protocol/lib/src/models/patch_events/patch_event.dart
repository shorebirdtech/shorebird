import 'package:shorebird_code_push_protocol/src/models/patch_events/patch_events.dart';

export 'patch_install_event.dart';

/// {@template patch_event}
/// Base class for patch events.
/// {@endtemplate}
abstract class PatchEvent {
  /// {@macro patch_event}
  const PatchEvent({required this.type});

  /// Converts a Map<String, dynamic> to a [PatchEvent]
  factory PatchEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case PatchInstallEvent.identifier:
        return PatchInstallEvent.fromJson(json);
      default:
        throw ArgumentError.value(
          type,
          'type',
          'Invalid patch event type',
        );
    }
  }

  /// The type of patch event.
  final String type;

  /// Converts a [PatchEvent] to a Map<String, dynamic>
  Map<String, dynamic> toJson();
}
