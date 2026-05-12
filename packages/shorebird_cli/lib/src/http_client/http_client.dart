import 'package:http/http.dart' as http;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_code_push_client/shorebird_code_push_client.dart';
import 'package:shorebird_cli/src/http_client/logging_client.dart';
import 'package:shorebird_cli/src/http_client/retrying_client.dart';
import 'package:shorebird_cli/src/http_client/tracing_client.dart';

export 'logging_client.dart';
export 'retrying_client.dart';
export 'tracing_client.dart';

/// A reference to a [http.Client] instance.
///
/// The bottom of the stack is [CodePushClient.buildDefaultHttpClient], which
/// applies a connection-level timeout so unreachable hosts surface as
/// transport errors instead of hanging.
final httpClientRef = create<http.Client>(
  () => TracingClient(
    httpClient: retryingHttpClient(
      LoggingClient(httpClient: CodePushClient.buildDefaultHttpClient()),
    ),
  ),
);

/// The [http.Client] instance available in the current zone.
http.Client get httpClient => read(httpClientRef);
