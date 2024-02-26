// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart';

import 'src/auth_http_utils.dart';
import 'src/oauth2_flows/authorization_code_grant_manual_flow.dart';
import 'src/oauth2_flows/authorization_code_grant_server_flow.dart';

export 'googleapis_auth.dart';
export 'src/metadata_server_client.dart';
export 'src/oauth2_flows/auth_code.dart'
    show obtainAccessCredentialsViaCodeExchange;
export 'src/service_account_client.dart';
export 'src/typedefs.dart';

/// Obtains oauth2 credentials and returns an authenticated HTTP client.
///
/// See [obtainAccessCredentialsViaUserConsent] for specifics about the
/// arguments used for obtaining access credentials.
///
/// {@macro googleapis_auth_clientId_param}
///
/// {@macro googleapis_auth_returned_auto_refresh_client}
///
/// {@macro googleapis_auth_baseClient_param}
///
/// {@template googleapis_auth_hostedDomain_param}
/// If provided, restricts sign-in to Google Apps hosted accounts at
/// [hostedDomain]. For more details, see
/// https://developers.google.com/identity/protocols/oauth2/openid-connect#hd-param
/// {@endtemplate}
///
/// {@macro googleapis_auth_close_the_client}
/// {@macro googleapis_auth_not_close_the_baseClient}
/// {@macro googleapis_auth_listen_port}
Future<AutoRefreshingAuthClient> clientViaUserConsent(
  AuthEndpoints authEndpoints,
  ClientId clientId,
  List<String> scopes,
  PromptUserForConsent userPrompt, {
  Client? baseClient,
  String? hostedDomain,
  int listenPort = 0,
}) async {
  var closeUnderlyingClient = false;
  if (baseClient == null) {
    baseClient = Client();
    closeUnderlyingClient = true;
  }

  final flow = AuthorizationCodeGrantServerFlow(
    authEndpoints,
    clientId,
    scopes,
    baseClient,
    userPrompt,
    hostedDomain: hostedDomain,
    listenPort: listenPort,
  );

  AccessCredentials credentials;

  try {
    credentials = await flow.run();
  } catch (e) {
    if (closeUnderlyingClient) {
      baseClient.close();
    }
    rethrow;
  }
  return AutoRefreshingClient(
    baseClient,
    authEndpoints,
    clientId,
    credentials,
    closeUnderlyingClient: closeUnderlyingClient,
  );
}

/// Obtains oauth2 credentials and returns an authenticated HTTP client.
///
/// See [obtainAccessCredentialsViaUserConsentManual] for specifics about the
/// arguments used for obtaining access credentials.
///
/// {@macro googleapis_auth_clientId_param}
///
/// {@macro googleapis_auth_returned_auto_refresh_client}
///
/// {@macro googleapis_auth_baseClient_param}
///
/// {@macro googleapis_auth_hostedDomain_param}
///
/// {@macro googleapis_auth_close_the_client}
/// {@macro googleapis_auth_not_close_the_baseClient}
Future<AutoRefreshingAuthClient> clientViaUserConsentManual(
  AuthEndpoints authEndpoints,
  ClientId clientId,
  List<String> scopes,
  PromptUserForConsentManual userPrompt, {
  Client? baseClient,
  String? hostedDomain,
}) async {
  var closeUnderlyingClient = false;
  if (baseClient == null) {
    baseClient = Client();
    closeUnderlyingClient = true;
  }

  final flow = AuthorizationCodeGrantManualFlow(
    authEndpoints,
    clientId,
    scopes,
    baseClient,
    userPrompt,
    hostedDomain: hostedDomain,
  );

  AccessCredentials credentials;

  try {
    credentials = await flow.run();
  } catch (e) {
    if (closeUnderlyingClient) {
      baseClient.close();
    }
    rethrow;
  }

  return AutoRefreshingClient(
    baseClient,
    authEndpoints,
    clientId,
    credentials,
    closeUnderlyingClient: closeUnderlyingClient,
  );
}

/// Obtain oauth2 [AccessCredentials] using the oauth2 authentication code flow.
///
/// {@macro googleapis_auth_clientId_param}
///
/// [userPrompt] will be used for directing the user/user-agent to a URI. See
/// [PromptUserForConsent] for more information.
///
/// {@macro googleapis_auth_client_for_creds}
///
/// {@macro googleapis_auth_hostedDomain_param}
///
/// {@macro googleapis_auth_user_consent_return}
///
/// {@template googleapis_auth_listen_port}
/// The `localhost` port to use when listening for the redirect from a user
/// browser interaction. Defaults to `0` - which means the port is dynamic.
///
/// Generally you want to specify an explicit port so you can configure it
/// on the Google Cloud console.
/// {@endtemplate}
Future<AccessCredentials> obtainAccessCredentialsViaUserConsent(
  AuthEndpoints authEndpoints,
  ClientId clientId,
  List<String> scopes,
  Client client,
  PromptUserForConsent userPrompt, {
  String? hostedDomain,
  int listenPort = 0,
}) =>
    AuthorizationCodeGrantServerFlow(
      authEndpoints,
      clientId,
      scopes,
      client,
      userPrompt,
      hostedDomain: hostedDomain,
      listenPort: listenPort,
    ).run();

/// Obtain oauth2 [AccessCredentials] using the oauth2 authentication code flow.
///
/// {@macro googleapis_auth_clientId_param}
///
/// [userPrompt] will be used for directing the user/user-agent to a URI. See
/// [PromptUserForConsentManual] for more information.
///
/// {@macro googleapis_auth_client_for_creds}
///
/// {@macro googleapis_auth_hostedDomain_param}
///
/// {@macro googleapis_auth_user_consent_return}
Future<AccessCredentials> obtainAccessCredentialsViaUserConsentManual(
  AuthEndpoints authEndpoints,
  ClientId clientId,
  List<String> scopes,
  Client client,
  PromptUserForConsentManual userPrompt, {
  String? hostedDomain,
}) =>
    AuthorizationCodeGrantManualFlow(
      authEndpoints,
      clientId,
      scopes,
      client,
      userPrompt,
      hostedDomain: hostedDomain,
    ).run();
