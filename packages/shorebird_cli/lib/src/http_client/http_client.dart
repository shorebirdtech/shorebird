import 'package:http/http.dart' as http;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/http_client/logging_client.dart';
import 'package:shorebird_cli/src/http_client/retrying_client.dart';
import 'package:shorebird_cli/src/http_client/tracing_client.dart';
import 'package:shorebird_cli/src/http_client/user_agent_client.dart';

export 'logging_client.dart';
export 'retrying_client.dart';
export 'tracing_client.dart';
export 'user_agent_client.dart';

/// A reference to a [http.Client] instance.
final httpClientRef = create<http.Client>(
  () => TracingClient(
    httpClient: retryingHttpClient(
      LoggingClient(httpClient: UserAgentClient(httpClient: http.Client())),
    ),
  ),
);

/// The [http.Client] instance available in the current zone.
http.Client get httpClient => read(httpClientRef);

/// A reference to an [http.Client] that does not retry, for requests that
/// must not be sent twice, such as an OIDC token exchange, whose ID token the
/// auth service accepts only once.
final nonRetryingHttpClientRef = create<http.Client>(
  () => TracingClient(
    httpClient: LoggingClient(
      httpClient: UserAgentClient(httpClient: http.Client()),
    ),
  ),
);

/// The non-retrying [http.Client] instance available in the current zone.
http.Client get nonRetryingHttpClient => read(nonRetryingHttpClientRef);
