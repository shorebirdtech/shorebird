import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';

void showiOSStatusWarning() {
  final url = link(
    uri: Uri.parse('https://docs.shorebird.dev/status'),
  );
  logger
    ..warn('iOS support is beta. Some apps may run slower after patching.')
    ..info('See $url for more information.');
}
