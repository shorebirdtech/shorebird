// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@TestOn('browser')
@Timeout.factor(4)
library;

import 'dart:html';
import 'dart:js' as js;

import 'package:googleapis_auth/auth_browser.dart' as auth;
import 'package:googleapis_auth/src/browser_utils.dart' as browser_utils;
import 'package:googleapis_auth/src/oauth2_flows/implicit.dart' as impl;
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  test('gapi-load-failure', () {
    impl.gapiUrl = resource('non_existent.js');
    expect(
      // ignore: deprecated_member_use_from_same_package
      auth.createImplicitBrowserFlow(_clientId, _scopes),
      throwsA(isA<auth.AuthenticationException>()),
    );
  });

  test('gapi-load-failure--syntax-error', () async {
    impl.gapiUrl = resource('gapi_load_failure.js');

    // Reset test_controller.js's window.onerror registration.
    // This makes sure we can catch the onError callback when the syntax error
    // is produced.
    js.context['onerror'] = null;

    window.onError.listen(expectAsync1((error) {
      error.preventDefault();
    }));

    final sw = Stopwatch()..start();
    try {
      // ignore: deprecated_member_use_from_same_package
      await auth.createImplicitBrowserFlow(_clientId, _scopes);
      fail('expected error');
    } catch (error) {
      final elapsed = (sw.elapsed - browser_utils.callbackTimeout).inSeconds;
      expect(elapsed, inInclusiveRange(-3, 3));
    }
  });
}

final _clientId = auth.ClientId('a', 'b');
const _scopes = ['scope1', 'scope2'];
