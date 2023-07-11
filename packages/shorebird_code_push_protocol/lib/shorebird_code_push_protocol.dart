/// The Shorebird CodePush Protocol
library shorebird_code_push_protocol;

export 'package:money2/money2.dart' show Currency, Money;
export 'src/converters/converters.dart';
export 'src/messages/messages.dart';
export 'src/models/models.dart';

/// Parsed JSON data.
typedef Json = Map<String, dynamic>;
