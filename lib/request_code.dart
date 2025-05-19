// Modified request_code.dart to support external browser authentication for Android 10 only
// Will NOT fall back to WebView after external browser failure

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'model/config.dart';
import 'request/authorization_request.dart';
import 'helper/android_version_checker.dart';

class RequestCode {
  final StreamController<String?> _onCodeListener = StreamController();
  final Config _config;
  late AuthorizationRequest _authorizationRequest;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();

  // Flag to track external auth attempt
  bool _externalAuthAttempted = false;

  Stream<String?>? _onCodeStream;

  RequestCode(Config config) : _config = config {
    _authorizationRequest = AuthorizationRequest(config);
  }

  Stream<String?> get _onCode {
    return _onCodeStream ??= _onCodeListener.stream.asBroadcastStream();
  }

  Future<String?> requestCode({required bool externalLogin}) async {
    // Reset the flag at the start of each request
    _externalAuthAttempted = false;

    // Create the authorization URL with parameters
    final Map<String, String> params = _authorizationRequest.parameters;

    // Ensure client_id is included
    if (!params.containsKey('client_id') && _config.clientId.isNotEmpty) {
      params['client_id'] = _config.clientId;
    }

    // Convert parameters to URL query string
    final String urlParams = params.entries
        .map((e) => "${e.key}=${Uri.encodeComponent(e.value)}")
        .join("&");

    final String initialURL =
        ('${_authorizationRequest.url}?$urlParams').replaceAll(' ', '%20');

    print('Authorization URL: $initialURL');
    print('Redirect URI: ${_config.redirectUri}');
    bool isAndroid10 = false;

    // Check for Android 10
    if (Platform.isAndroid) {
      try {
        isAndroid10 = await AndroidVersionChecker.isAndroid10();
        print('Is device Android 10? $isAndroid10');
      } catch (e) {
        print('Error checking Android version: $e');
        isAndroid10 = false;
      }
    }

    // some devices with Android 10 has a bug in the webview so it will always be external
    if (externalLogin || isAndroid10) {
      _externalAuthAttempted = true;

      try {
        // Use external browser flow with original redirect URI scheme
        final code = await _useExternalBrowserAuth(initialURL);
        return code;
      } catch (e) {
        print('EXTERNAL BROWSER AUTH FAILED: $e');
        // Propagate the error - do NOT fall back to WebView
        throw Exception('External browser authentication failed: $e');
      }
    }

    // Safety check - if external auth was attempted but failed,
    // we should NOT reach this point - throw error instead
    if (_externalAuthAttempted) {
      throw Exception(
          'External browser authentication failed - NOT falling back to WebView');
    }

    // For non-Android 10 devices, proceed with standard WebView approach
    if (_config.navigatorKey.currentContext != null) {
      await _useWebView(initialURL);
      final code = await _onCode.first;
      return code;
    } else {
      throw Exception('No valid Navigator context available');
    }
  }

  /// External browser authentication using flutter_web_auth
  Future<String?> _useExternalBrowserAuth(String url) async {
    try {
      // Extract the scheme from the redirect URI to use as callback
      final Uri redirectUri = Uri.parse(_config.redirectUri);
      final String callbackScheme = redirectUri.scheme;

      print('Using external browser with scheme: $callbackScheme');

      // Use flutter_web_auth with the actual redirect URI scheme
      final result = await FlutterWebAuth.authenticate(
        url: url,
        callbackUrlScheme: callbackScheme,
        preferEphemeral: true,
      );

      print('External browser auth completed, processing result');

      // Extract authorization code from result
      final Uri resultUri = Uri.parse(result);

      // Handle different response formats
      Map<String, String> resultParams = {};
      if (resultUri.queryParameters.isNotEmpty) {
        resultParams = resultUri.queryParameters;
      } else if (result.contains('#')) {
        // Handle fragment identifiers
        resultParams = Uri.parse(result.replaceFirst('#', '?')).queryParameters;
      }

      // Check for errors
      if (resultParams.containsKey('error')) {
        throw Exception(
            'Authentication error: ${resultParams['error']} - ${resultParams['error_description']}');
      }

      // Get authentication code
      final String? authCode = resultParams['code'];
      if (authCode == null || authCode.isEmpty) {
        throw Exception('No authorization code found in response');
      }

      print('Successfully received authorization code');
      return authCode;
    } catch (e) {
      print('External browser auth error: $e');
      // Re-throw to ensure proper error handling up the chain
      rethrow;
    }
  }

  /// WebView authentication for non-Android 10 devices
  Future<void> _useWebView(String url) async {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              return _handleNavigation(request.url);
            },
          ),
        )
        ..loadRequest(Uri.parse(url));

      await Navigator.of(_config.navigatorKey.currentContext!)
          .push(MaterialPageRoute(
              builder: (context) => SafeArea(
                    child: Scaffold(
                      body: Stack(
                        children: [
                          WebViewWidget(controller: controller),
                          _config.loader
                        ],
                      ),
                    ),
                  )));
    } catch (e) {
      print('WebView error: $e');
      throw Exception('WebView authentication failed: $e');
    }
  }

  /// Handle WebView navigation for redirect URI
  NavigationDecision _handleNavigation(String url) {
    if (url.startsWith(_config.redirectUri)) {
      Uri uri = Uri.parse(url);

      // Handle fragments
      if (url.contains('#')) {
        uri = Uri.parse(url.replaceFirst('#', '?'));
      }

      // Check for error
      if (uri.queryParameters.containsKey('error')) {
        _onCodeListener.addError(Exception(
            'Authentication denied: ${uri.queryParameters['error_description']}'));
        Navigator.of(_config.navigatorKey.currentContext!).pop();
        return NavigationDecision.prevent;
      }

      // Get auth code
      final String? code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        _onCodeListener.add(code);
        Navigator.of(_config.navigatorKey.currentContext!).pop();
        return NavigationDecision.prevent;
      }
    }

    return NavigationDecision.navigate;
  }

  Future<void> clearCookies() async {
    await _cookieManager.clearCookies();
  }
}
