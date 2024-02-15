import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import 'authentication_exception.dart';

Future<void> initializeScript(
  String scriptUrl, {
  String? onloadParam,
}) async {
  final instance = _ScriptLoader._instances.putIfAbsent(
    scriptUrl,
    () => _ScriptLoader._(scriptUrl, onloadParam: onloadParam),
  );

  await instance._initialize();
}

/// Creates a script that will run properly when strict CSP is enforced.
///
/// More specifically, the script has the correct `nonce` value set.
final html.ScriptElement Function() _createScriptTag = (() {
  final nonce = _getNonce();
  if (nonce == null) return html.ScriptElement.new;

  return () => html.ScriptElement()..nonce = nonce;
})();

/// Returns CSP nonce, if set for any script tag.
String? _getNonce({html.Window? window}) {
  final currentWindow = window ?? html.window;
  final elements = currentWindow.document.querySelectorAll('script');
  for (final element in elements) {
    final nonceValue =
        (element as html.HtmlElement).nonce ?? element.attributes['nonce'];
    if (nonceValue != null && _noncePattern.hasMatch(nonceValue)) {
      return nonceValue;
    }
  }
  return null;
}

// According to the CSP3 spec a nonce must be a valid base64 string.
// https://w3c.github.io/webappsec-csp/#grammardef-base64-value
final _noncePattern = RegExp('^[\\w+/_-]+[=]{0,2}\$');

const callbackTimeout = Duration(seconds: 20);

class _ScriptLoader {
  _ScriptLoader._(
    this.url, {
    this.onloadParam,
  });

  static final _instances = <String, _ScriptLoader>{};

  final String url;
  final String? onloadParam;

  Future<void>? _pendingInitialization;

  Future<void> _initialize() {
    if (_pendingInitialization != null) {
      return _pendingInitialization!;
    }

    final completer = Completer();

    final timeout = Timer(callbackTimeout, () {
      _pendingInitialization = null;
      completer.completeError(
        AuthenticationException(
          'Timed out while waiting for library to load: $url',
        ),
      );
    });

    void loadComplete() {
      timeout.cancel();
      completer.complete();
    }

    final loadFunctionName = '_dartScriptLoad_${url.hashCode}';

    js.context[loadFunctionName] = loadComplete;
    final fullUrl =
        onloadParam == null ? url : '$url?${onloadParam!}=$loadFunctionName';

    final script = _createScriptTag()
      ..async = true
      ..defer = true
      ..src = fullUrl;
    if (onloadParam == null) {
      script.onLoad.first.then((event) {
        loadComplete();
      });
    }
    script.onError.first.then((errorEvent) {
      timeout.cancel();
      _pendingInitialization = null;
      if (!completer.isCompleted) {
        // script loading errors can still happen after timeouts
        completer.completeError(
            AuthenticationException('Failed to load library: $url'));
      }
    });
    html.document.body!.append(script);

    _pendingInitialization = completer.future;
    return completer.future;
  }
}
