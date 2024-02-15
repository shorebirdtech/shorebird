// ignore_for_file: non_constant_identifier_names

@JS('google.accounts.oauth2')
library token_model_interop;

import 'package:js/js.dart';

@JS()
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#google.accounts.oauth2.initTokenClient
external TokenClient initTokenClient(TokenClientConfig config);

@JS()
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#google.accounts.oauth2.revoke
external void revoke(String accessToken, [void Function(Object?) done]);

@JS()
@anonymous
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#TokenClientConfig
class TokenClientConfig {
  external factory TokenClientConfig({
    required String client_id,
    required String scope,
    required void Function(TokenResponse) callback,
    String hint,
    String hosted_domain,
    String prompt,
  });

  // state: not recommended
  // enable_serial_consent: skipping. only for old clients
}

@JS()
@anonymous
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#TokenResponse
class TokenResponse {
  external String get access_token;
  external int get expires_in;
  external String get hd;
  external String get prompt;
  external String get token_type;
  external String get scope;

  /// A single ASCII error code.
  external String? get error;

  /// Human-readable ASCII text providing additional information, used to assist
  /// the client developer in understanding the error that occurred.
  external String? get error_description;

  /// A URI identifying a human-readable web page with information about the
  /// error, used to provide the client developer with additional information
  /// about the error.
  external String? get error_uri;
}

@JS()
@anonymous
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#google.accounts.oauth2.initTokenClient
class TokenClient {
  external void requestAccessToken();
}

@JS()
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#google.accounts.oauth2.initCodeClient
external CodeClient initCodeClient(CodeClientConfig config);

@JS()
@anonymous
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#CodeClient
class CodeClient {
  external void requestCode();
}

@JS()
@anonymous
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#CodeClientConfig
class CodeClientConfig {
  external factory CodeClientConfig({
    required String client_id,
    required String scope,
    String? redirect_uri,
    required void Function(CodeResponse) callback,
    String? state,
    String? hint,
    String? hosted_domain,
    String? ux_mode,
    bool select_account,
  });
}

@JS()
@anonymous
// https://developers.google.com/identity/oauth2/web/reference/js-reference?hl=en#CodeResponse
class CodeResponse {
  external String get code;
  external String get scope;
  external String? get state;

  external String get authuser;
  external String get hd;
  external String get prompt;

  /// A single ASCII error code.
  external String? get error;

  /// Human-readable ASCII text providing additional information, used to assist
  /// the client developer in understanding the error that occurred.
  external String? get error_description;

  /// A URI identifying a human-readable web page with information about the
  /// error, used to provide the client developer with additional information
  /// about the error.
  external String? get error_uri;
}
