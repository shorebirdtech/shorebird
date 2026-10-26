import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_cli/src/rollout_percentage.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Formats [patch] as the human-readable detail block rendered by
/// `shorebird patches info`, one line per entry. Optional fields (track,
/// notes, artifacts) are omitted when absent.
List<String> formatPatchDetails(ReleasePatch patch) => [
  'ID:          ${patch.id}',
  'Number:      ${patch.number}',
  if (formatPatchTrack(patch) case final track?) 'Track:       $track',
  'Rolled back: ${patch.isRolledBack ? 'yes' : 'no'}',
  if (patch.notes != null) 'Notes:       ${patch.notes}',
  if (patch.artifacts.isNotEmpty) ...[
    'Artifacts:',
    ...patch.artifacts.map(_formatArtifact),
  ],
];

String _formatArtifact(PatchArtifact artifact) {
  final platform = artifact.platform.value.padRight(8);
  final arch = artifact.arch.padRight(12);
  return '  $platform $arch ${formatBytes(artifact.size)}';
}

/// The track [patch] is on, followed by its rollout percentage when that is
/// below 100 (e.g. `stable (10%)`), or null when it is on no track.
String? formatPatchTrack(ReleasePatch patch) {
  final channel = patch.channel;
  if (channel == null) return null;
  final percentage = patch.rolloutPercentage;
  if (percentage == null || percentage >= 100) return channel;
  return '$channel (${formatRolloutPercentage(percentage)})';
}
