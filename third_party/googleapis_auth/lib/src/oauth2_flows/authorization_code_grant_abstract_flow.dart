// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:googleapis_auth/src/auth_provider.dart';
import 'package:http/http.dart' as http;

import '../access_credentials.dart';
import '../client_id.dart';
import 'auth_code.dart';
import 'base_flow.dart';

abstract class AuthorizationCodeGrantAbstractFlow implements BaseFlow {
  final AuthProvider authProvider;
  final ClientId clientId;
  final String? hostedDomain;
  final List<String> scopes;
  final http.Client _client;

  AuthorizationCodeGrantAbstractFlow(
    this.authProvider,
    this.clientId,
    this.scopes,
    this._client, {
    this.hostedDomain,
  });

  Future<AccessCredentials> obtainAccessCredentialsUsingCodeImpl(
    String code,
    String redirectUri, {
    required AuthProvider authProvider,
    required String codeVerifier,
  }) =>
      obtainAccessCredentialsViaCodeExchange(
        authProvider,
        _client,
        clientId,
        code,
        redirectUrl: redirectUri,
        codeVerifier: codeVerifier,
      );

  Uri authenticationUri(
    String redirectUri, {
    String? state,
    required String codeVerifier,
  }) =>
      createAuthenticationUri(
        authProvider: authProvider,
        redirectUri: redirectUri,
        clientId: clientId.identifier,
        scopes: scopes,
        codeVerifier: codeVerifier,
        hostedDomain: hostedDomain,
        state: state,
      );
}
