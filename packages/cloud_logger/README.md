# Cloud logger

[![License: MIT][license_badge]][license_link]

A Dart library for cloud logging

```dart
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
```

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
