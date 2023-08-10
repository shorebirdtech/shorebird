import 'package:json_annotation/json_annotation.dart';
import 'package:shorebird_code_push_protocol/src/models/patch_events/patch_events.dart';

part 'create_patch_event_request.g.dart';

/// {@template create_patch_event_request}
/// Request to create a patch event.
/// {@endtemplate}
@JsonSerializable()
class CreatePatchEventRequest {
  /// {@macro create_patch_event_request}
  CreatePatchEventRequest({required this.event});

  /// Converts a Map<String, dynamic> to a [CreatePatchEventRequest]
  factory CreatePatchEventRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePatchEventRequestFromJson(json);

  /// Converts a [CreatePatchEventRequest] to a Map<String, dynamic>
  Map<String, dynamic> toJson() => _$CreatePatchEventRequestToJson(this);

  /// The event being created.
  final PatchEvent event;
}
