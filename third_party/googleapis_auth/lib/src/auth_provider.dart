import 'known_uris.dart';

/// The entity being used to authenticate the user.
enum AuthProvider {
  google,
  microsoft,
}

extension Endpoints on AuthProvider {
  Uri get authorizationEndpoint {
    switch (this) {
      case AuthProvider.google:
        return googleOauth2AuthorizationEndpoint;
      case AuthProvider.microsoft:
        return microsoftOauth2AuthorizationEndpoint;
    }
  }

  Uri get tokenEndpoint {
    switch (this) {
      case AuthProvider.google:
        return googleOauth2TokenEndpoint;
      case AuthProvider.microsoft:
        return microsoftTokenEndpoint;
    }
  }
}
