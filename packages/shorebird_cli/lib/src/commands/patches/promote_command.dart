import 'package:shorebird_cli/src/commands/patches/set_track_command.dart';
import 'package:shorebird_cli/src/deployment_track.dart';
import 'package:shorebird_cli/src/shorebird_command.dart';

const _jsonExample =
    'shorebird patches promote --release-version 1.0.0+1 --patch-number 1 '
    '--app-id <id> --json';

/// {@template promote_command}
/// Moves a patch to a track, `stable` unless `--track` says otherwise.
///
/// The same command as `shorebird patches set-track`, with `--track`
/// defaulting to `stable`. Promoting a patch to production is the common case,
/// and `patches promote` is the name people and agents reach for first.
/// {@endtemplate}
class PromoteCommand extends SetTrackCommand {
  /// {@macro promote_command}
  PromoteCommand() : super(defaultTrack: DeploymentTrack.stable.channel);

  @override
  String get name => 'promote';

  @override
  String get description =>
      'Promotes a patch to the "stable" track, or to --track. '
      'Same as `shorebird patches set-track --track stable`.\n\n'
      'Example output:\n'
      '  Patch 1 on release 1.0.0+1 is now in channel stable!\n\n'
      '${ShorebirdCommand.jsonHint(_jsonExample)}';
}
