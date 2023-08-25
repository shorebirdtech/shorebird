import 'package:args/command_runner.dart';
import 'package:cutler/checkout.dart';
import 'package:cutler/config.dart';
import 'package:cutler/cutler.dart';
import 'package:cutler/logger.dart';

/// Base class for Cutler subcommands.
abstract class CutlerCommand extends Command<int> {
  /// Constructs a new [CutlerCommand].
  CutlerCommand();

  /// The global config, set during argument parsing.
  Config get config => (runner! as Cutler).config;

  /// The checkout objects
  late final Checkouts checkouts;

  /// The Flutter checkout.
  Checkout get flutter => checkouts.flutter;

  /// The Engine checkout.
  Checkout get engine => checkouts.engine;

  /// The Shorebird checkout.
  Checkout get shorebird => checkouts.shorebird;

  /// The Buildroot checkout.
  Checkout get buildroot => checkouts.buildroot;

  /// The Dart checkout.
  Checkout get dart => checkouts.dart;

  /// Update the repos if needed.
  void updateReposIfNeeded(Config config) {
    if (!config.doUpdate) {
      return;
    }
    final progress = logger.progress('Updating checkouts...');
    for (final checkout in checkouts.values) {
      progress.update('Updating ${checkout.name}');
      checkout.fetchAll();
    }
    progress.complete('Checkouts updated!');
  }
}
