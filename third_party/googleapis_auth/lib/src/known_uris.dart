// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// token_endpoint
/// via https://accounts.google.com/.well-known/openid-configuration
final googleOauth2TokenEndpoint = Uri.https('oauth2.googleapis.com', 'token');

/// authorization_endpoint
/// via https://accounts.google.com/.well-known/openid-configuration
final googleOauth2AuthorizationEndpoint =
    Uri.https('accounts.google.com', 'o/oauth2/v2/auth');

/// via https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#request-an-access-token-with-a-certificate-credential
final microsoftTokenEndpoint =
    Uri.https('login.microsoftonline.com', 'common/oauth2/v2.0/token');

/// via https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-auth-code-flow#request-an-authorization-code
final microsoftOauth2AuthorizationEndpoint =
    Uri.https('login.microsoftonline.com', 'common/oauth2/v2.0/authorize');
