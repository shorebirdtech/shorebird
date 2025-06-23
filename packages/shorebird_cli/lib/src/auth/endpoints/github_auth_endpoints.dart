// cspell:words microsoftonline
import 'package:googleapis_auth/googleapis_auth.dart';

/// {@template github_auth_endpoints}
/// Endpoints for OAuth authentication with GitHub.
/// {@endtemplate}
class GithubAuthEndpoints extends AuthEndpoints {
  /// {@macro github_auth_endpoints}
  const GithubAuthEndpoints();

  @override
  Uri get authorizationEndpoint =>
      Uri.https('github.com', 'login/oauth/authorize');

  @override
  Uri get tokenEndpoint => Uri.https('github.com', 'login/oauth/access_token');
}
