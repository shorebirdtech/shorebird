import 'known_uris.dart';

abstract class AuthProvider {
  Uri get authorizationEndpoint;
  Uri get tokenEndpoint;
}

class GoogleAuthProvider extends AuthProvider {
  @override
  Uri get authorizationEndpoint => googleOauth2AuthorizationEndpoint;

  @override
  Uri get tokenEndpoint => googleOauth2TokenEndpoint;
}
