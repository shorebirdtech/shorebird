import 'package:shorebird_cli/src/formatters/file_size_formatter.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Formats [patch] as the human-readable detail block rendered by
/// `shorebird patches info`, one line per entry. Optional fields (track,
/// notes, artifacts) are omitted when absent.
List<String> formatPatchDetails(ReleasePatch patch) => [
  'ID:          ${patch.id}',
  'Number:      ${patch.number}',
  if (patch.channel != null) 'Track:       ${patch.channel}',
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
