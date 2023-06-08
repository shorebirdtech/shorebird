import 'package:shorebird_cli/src/command.dart';
import 'package:shorebird_cli/src/commands/subscription/subscription.dart';

/// {@template subscription_command}
///
/// `shorebird subscription`
/// Manage your Shorebird subscription.
/// {@endtemplate}
class SubscriptionCommand extends ShorebirdCommand {
  /// {@macro subscription_command}
  SubscriptionCommand() {
    addSubcommand(CancelSubscriptionCommand());
  }

  @override
  String get name => 'subscription';

  @override
  String get description => 'Manage your Shorebird subscription.';
}
