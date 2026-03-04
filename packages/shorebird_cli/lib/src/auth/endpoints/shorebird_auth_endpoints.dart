import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:shorebird_cli/src/shorebird_env.dart';

/// Endpoints for OAuth authentication with the Shorebird auth service.
///
/// The Shorebird auth service doesn't use traditional OAuth endpoints, but
/// `AuthenticatedClient` passes `authEndpoints` through to the refresh
/// function. The Shorebird refresh function ignores this parameter, so these
/// values exist only to satisfy the type system.
class ShorebirdAuthEndpoints extends AuthEndpoints {
  @override
  Uri get authorizationEndpoint =>
      shorebirdEnv.authServiceUri.replace(path: '/login');

  @override
  Uri get tokenEndpoint =>
      shorebirdEnv.authServiceUri.replace(path: '/token');
}
