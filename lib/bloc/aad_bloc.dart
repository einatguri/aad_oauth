import 'dart:async';
import 'package:aad_oauth/model/token.dart';
import 'package:aad_oauth/repository/token_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:webview_flutter/webview_flutter.dart';

part 'aad_event.dart';
part 'aad_state.dart';

class AadBloc extends Bloc<AadEvent, AadState> {
  AadBloc({
    required this.tokenRepository,
  }) : super(AadInitialState()) {
    add(AadLoginRequestEvent());
  }
  final TokenRepository tokenRepository;

  @override
  Stream<AadState> mapEventToState(
    AadEvent event,
  ) async* {
    if (event is AadLoginRequestEvent) {
      if (state is AadSignedOutState ||
          state is AadInternalErrorState ||
          state is AadAuthenticationFailedState) {
        yield AadInitialState();
      }
      yield await processLoginRequested();
    } else if (event is AadTokenRefreshRequestEvent) {
      yield await processAccessTokenRefresh();
    } else if (event is AadLogoutRequestEvent) {
      await CookieManager().clearCookies();
      await tokenRepository.clearTokenFromCache();
      yield AadSignedOutState();
    } else if (event is AadFullFlowUrlLoadedEvent) {
      yield await processFullLoginFlowPageLoadUrl(event.url);
    } else if (event is AadSignInErrorEvent) {
      yield await AadInternalErrorState(event.description);
    } else if (event is AadDebugTokenEvent) {
      await tokenRepository.saveTokenToCache(event.debugToken);
      yield AadAuthenticatedState(token: event.debugToken);
    } else {
      yield AadInternalErrorState(
          'Unexpected/unhandled AadEvent type ${event} received');
    }
  }

  Future<AadState> processFullLoginFlowPageLoadUrl(String url) async {
    var uri = Uri.parse(url);

    if (uri.queryParameters['error'] != null) {
      return AadAuthenticationFailedState();
    }
    final code = uri.queryParameters['code'];
    if (code != null) {
      final token = await tokenRepository.requestTokenWithCode(code);
      if (token.hasValidAccessToken()) {
        return AadAuthenticatedState(token: token);
      } else {
        return AadAuthenticationFailedState();
      }
    }
    return state;
  }

  Future<AadState> processLoginRequested() async {
    try {
      final token = await tokenRepository.loadTokenFromCache();
      if (token.hasValidAccessToken()) {
        return AadAuthenticatedState(token: token);
      } else if (token.hasRefreshToken()) {
        return await _processRefreshWithToken(token);
      }
    } catch (e) {
      print(e);
    }
    return AadFullFlowState();
  }

  Future<AadState> processAccessTokenRefresh() async {
    final aState = state;
    if (aState is AadWithTokenState) {
      final token = aState.token;

      return await _processRefreshWithToken(token);
    } else {
      // If state has no token, we always attempt full flow
      return AadFullFlowState();
    }
  }

  Future<AadState> _processRefreshWithToken(Token token) async {
    try {
      final newToken = await tokenRepository.refreshAccessTokenFlow(token);
      if (newToken.hasValidAccessToken()) {
        await tokenRepository.saveTokenToCache(newToken);
        return AadAuthenticatedState(token: newToken);
      } else {
        await tokenRepository.clearTokenFromCache();
      }
    } catch (e) {
      print(e);
    }
    // Fall-through is full flow
    return AadFullFlowState();
  }
}