// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import '../access_credentials.dart';
import '../access_token.dart';
import '../authentication_exception.dart';
import '../browser_utils.dart';
import '../exceptions.dart';
import '../response_type.dart';

// This will be overridden by tests.
String gapiUrl = 'https://apis.google.com/js/client.js';

/// This class performs the implicit browser-based oauth2 flow.
///
/// It has to be used in two steps:
///
/// 1. First call initialize() and wait until the Future completes successfully
///    - loads the 'gapi' JavaScript library into the current document
///    - wait until the library signals it is ready
///
/// 2. Call login() as often as needed.
///    - will call the 'gapi' JavaScript lib to trigger an oauth2 browser flow
///      => This might create a popup which asks the user for consent.
///    - will wait until the flow is completed (successfully or not)
///      => Completes with AccessToken or an Exception.
/// 3. Call loginHybrid() as often as needed.
///    - will call the 'gapi' JavaScript lib to trigger an oauth2 browser flow
///      => This might create a popup which asks the user for consent.
///    - will wait until the flow is completed (successfully or not)
///      => Completes with a tuple [AccessCredentials cred, String authCode]
///         or an Exception.
class ImplicitFlow {
  final String _clientId;
  final List<String> _scopes;
  final bool _enableDebugLogs;

  ImplicitFlow(this._clientId, this._scopes, this._enableDebugLogs);

  /// Readies the flow for calls to [login] by loading the 'gapi'
  /// JavaScript library, or returning the [Future] of a pending
  /// initialization if any object has called this method already.
  Future<void> initialize() async {
    await initializeScript(gapiUrl, onloadParam: 'onload');
    if (_enableDebugLogs) _gapiAuth2.callMethod('enableDebugLogs', [true]);
  }

  Future<LoginResult> loginHybrid({
    String? prompt,
    String? loginHint,
    String? hostedDomain,
  }) =>
      _login(
        prompt: prompt,
        responseTypes: [ResponseType.code, ResponseType.token],
        loginHint: loginHint,
        hostedDomain: hostedDomain,
      );

  Future<AccessCredentials> login({
    String? prompt,
    String? loginHint,
    List<ResponseType>? responseTypes,
    String? hostedDomain,
  }) async =>
      (await _login(
        prompt: prompt,
        loginHint: loginHint,
        responseTypes: responseTypes,
        hostedDomain: hostedDomain,
      ))
          .credential;

  // Completes with either credentials or a tuple of credentials and authCode.
  //  hybrid  =>  [AccessCredentials credentials, String authCode]
  // !hybrid  =>  AccessCredentials
  //
  // Alternatively, the response types can be set directly if `hybrid` is not
  // set to `true`.
  Future<LoginResult> _login({
    required String? prompt,
    required String? hostedDomain,
    required String? loginHint,
    required List<ResponseType>? responseTypes,
  }) {
    final completer = Completer<LoginResult>();

    // https://developers.google.com/identity/sign-in/web/reference#gapiauth2authorizeconfig
    final json = {
      'client_id': _clientId,
      'scope': _scopes.join(' '),
      'response_type': responseTypes == null || responseTypes.isEmpty
          ? 'token'
          : responseTypes.map(_responseTypeToString).join(' '),
      if (prompt != null) 'prompt': prompt,
      // cookie_policy – missing
      if (hostedDomain != null) 'hosted_domain': hostedDomain,
      if (loginHint != null) 'login_hint': loginHint,
      // include_granted_scopes - missing
      'plugin_name': 'dart-googleapis_auth',
    };

    _gapiAuth2.callMethod('authorize', [
      js.JsObject.jsify(json),
      (js.JsObject jsTokenObject) {
        try {
          final result = _processToken(jsTokenObject, responseTypes);
          completer.complete(result);
        } catch (e, stack) {
          html.window.console.error(jsTokenObject);
          completer.completeError(e, stack);
        }
      }
    ]);

    return completer.future;
  }

  LoginResult _processToken(
    js.JsObject jsTokenObject,
    List<ResponseType>? responseTypes,
  ) {
    final error = jsTokenObject['error'];

    if (error != null) {
      final details = jsTokenObject['details'] as String?;
      throw UserConsentException(
        'Failed to get user consent: $error.',
        details: details,
      );
    }

    final tokenType = jsTokenObject['token_type'];
    final token = jsTokenObject['access_token'] as String?;

    if (token == null || tokenType != 'Bearer') {
      throw AuthenticationException(
        'Failed to obtain user consent. Invalid server response.',
      );
    }

    final idToken = jsTokenObject['id_token'] as String?;

    if (responseTypes?.contains(ResponseType.idToken) == true &&
        idToken?.isNotEmpty != true) {
      throw AuthenticationException('Expected to get id_token, but did not.');
    }

    final scopeString = jsTokenObject['scope'] as String;
    final scopes = scopeString.split(' ');

    final expiresAt = jsTokenObject['expires_at'] as int;
    final expiresAtDate =
        DateTime.fromMillisecondsSinceEpoch(expiresAt).toUtc();

    final accessToken = AccessToken('Bearer', token, expiresAtDate);

    final credentials = AccessCredentials(
      accessToken,
      null,
      scopes,
      idToken: idToken,
    );

    String? code;
    if (responseTypes?.contains(ResponseType.code) == true) {
      code = jsTokenObject['code'] as String?;

      if (code == null) {
        throw AuthenticationException(
          'Expected to get auth code from server in hybrid flow, but did not.',
        );
      }
    }
    return LoginResult(credentials, code: code);
  }
}

class LoginResult {
  final AccessCredentials credential;
  final String? code;

  LoginResult(this.credential, {this.code});
}

/// Convert [responseType] to string value expected by `gapi.auth.authorize`.
String _responseTypeToString(ResponseType responseType) {
  switch (responseType) {
    case ResponseType.code:
      return 'code';
    case ResponseType.idToken:
      return 'id_token';
    case ResponseType.permission:
      return 'permission';
    case ResponseType.token:
      return 'token';
  }
}

js.JsObject get _gapiAuth2 =>
    (js.context['gapi'] as js.JsObject)['auth2'] as js.JsObject;
