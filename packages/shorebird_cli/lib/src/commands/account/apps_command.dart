import 'package:shorebird_cli/src/shorebird_command.dart';

/// {@template account_apps_command}
/// `shorebird account apps`
/// Moved to `shorebird apps list`, which it duplicated. Kept hidden so that
/// scripts and agents that still call it learn the replacement.
/// {@endtemplate}
class AccountAppsCommand extends ShorebirdCommand {
  /// {@macro account_apps_command}
  AccountAppsCommand();

  /// What to run instead.
  static const replacement = 'shorebird apps list';

  @override
  String get name => 'apps';

  @override
  bool get hidden => true;

  @override
  String get description => 'Moved to `$replacement`.';

  @override
  Future<int> run() async {
    return reportError(
      message: '`shorebird account apps` has moved to `$replacement`.',
      hint: 'Run: $replacement',
      exitCode: 1,
    );
  }
}
