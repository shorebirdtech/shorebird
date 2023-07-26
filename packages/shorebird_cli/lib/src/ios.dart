import 'package:mason_logger/mason_logger.dart';
import 'package:shorebird_cli/src/logger.dart';

void showiOSStatusWarning() {
  final url =
      link(uri: Uri.parse('https://docs.shorebird.dev/status#ios-alpha'));
  logger.warn('iOS support is alpha. See $url for more information.');
}
