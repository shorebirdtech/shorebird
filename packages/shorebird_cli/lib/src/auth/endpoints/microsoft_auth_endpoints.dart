import 'package:googleapis_auth/googleapis_auth.dart';

/// Endpoints for OAuth authentication with Azure/Entra/Microsoft.
class MicrosoftAuthEndpoints extends AuthEndpoints {
  @override
  Uri get authorizationEndpoint =>
      Uri.https('login.microsoftonline.com', 'common/oauth2/v2.0/authorize');

  @override
  Uri get tokenEndpoint =>
      Uri.https('login.microsoftonline.com', 'common/oauth2/v2.0/token');
}
