import 'package:http/http.dart' as http;
import 'package:scoped/scoped.dart';
import 'package:shorebird_cli/src/http_client/logging_client.dart';
import 'package:shorebird_cli/src/http_client/retrying_client.dart';

export 'logging_client.dart';
export 'retrying_client.dart';

/// A reference to a [http.Client] instance.
final httpClientRef = create(
  () => retryingHttpClient(
    LoggingClient(httpClient: http.Client()),
  ),
);

/// The [http.Client] instance available in the current zone.
http.Client get httpClient => read(httpClientRef);
