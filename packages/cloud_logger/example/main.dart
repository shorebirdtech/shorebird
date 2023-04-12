import 'package:cloud_logger/cloud_logger.dart';

void main() {
  logger
    ..info('info')
    ..debug('debug')
    ..notice('notice')
    ..warning('warning')
    ..error('error')
    ..critical('critical')
    ..alert('alert')
    ..emergency('emergency');
}
