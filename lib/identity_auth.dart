import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'auth_config.dart';
import 'auth_validation.dart';

class DriverAuthException implements Exception {
  const DriverAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class DriverActivationRequired implements Exception {
  const DriverActivationRequired();
}

class IdentitySession {
  const IdentitySession(this.accessToken, this.refreshToken, this.expiresIn);
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory IdentitySession.fromJson(Map<String, dynamic> json) {
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expiry = json['expires_in'];
    if (access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        expiry is! num ||
        expiry <= 0) {
      throw const DriverAuthException(
        'Sign-in could not be verified. Try again.',
      );
    }
    return IdentitySession(access, refresh, expiry.toInt());
  }
}

class GoogleIdentityTokens {
  const GoogleIdentityTokens(this.idToken, this.accessToken);
  final String idToken;
  final String accessToken;
}

/// Uses Supabase's public Auth API. This class never grants a HireD driver role.
/// DriverAuth verifies membership with the existing driver service separately.
class SupabaseIdentityAuth {
  SupabaseIdentityAuth(
    this.config, {
    http.Client? client,
    this.googleTokenProvider,
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final DriverAuthConfig config;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;
  final Future<GoogleIdentityTokens?> Function()? googleTokenProvider;
  static Future<void>? _googleInitialization;

  void dispose() {
    if (_ownsClient) _client.close();
  }

  void requireConfigured() {
    if (!config.isConfigured) {
      throw const DriverAuthException(
        'This sign-in method is being set up. Please contact HireD support.',
      );
    }
    final uri = Uri.tryParse(config.supabaseUrl);
    final local = uri?.host == '127.0.0.1' || uri?.host == 'localhost';
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && !(kDebugMode && local))) {
      throw const DriverAuthException('Sign-in is temporarily unavailable.');
    }
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    required Map<String, dynamic> body,
    String? bearer,
  }) async {
    requireConfigured();
    final base = config.supabaseUrl.replaceFirst(RegExp(r'/$'), '');
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('$base/auth/v1/$path'),
            headers: {
              'apikey': config.publishableKey,
              'Content-Type': 'application/json',
              if (bearer != null) 'Authorization': 'Bearer $bearer',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const DriverAuthException(
        'Sign-in took too long. Please try again.',
      );
    } on http.ClientException {
      throw const DriverAuthException(
        'Unable to connect. Check your internet and try again.',
      );
    }
    if (response.statusCode == 429) {
      throw const DriverAuthException(
        'Too many attempts. Please wait a minute and try again.',
      );
    }
    if (response.statusCode >= 500) {
      throw const DriverAuthException(
        'Sign-in is temporarily unavailable. Please try again later.',
      );
    }
    Map<String, dynamic> payload;
    try {
      payload = response.body.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const DriverAuthException(
        'Sign-in returned an unexpected response. Please try again.',
      );
    }
    if (response.statusCode >= 400) {
      final code = payload['error_code'] ?? payload['code'] ?? payload['error'];
      if (code == 'otp_expired' || code == 'access_denied') {
        throw const DriverAuthException(
          'The code is incorrect or expired. Please try again or request a new code.',
        );
      }
      if (code == 'phone_provider_disabled' || code == 'otp_disabled') {
        throw const DriverAuthException(
          'SMS sign-in is not configured yet. Please use email sign-in or contact HireD support.',
        );
      }
      if (code == 'provider_disabled' ||
          code == 'sms_send_failed' ||
          code == 'validation_failed') {
        throw const DriverAuthException(
          'This sign-in method is unavailable. Please contact HireD support.',
        );
      }
      if (code == 'signup_disabled' || code == 'user_not_found') {
        throw const DriverAuthException(
          'Unable to continue with this number. Try registering or contact HireD support.',
        );
      }
      throw const DriverAuthException(
        'We could not verify your sign-in. Check your details and try again.',
      );
    }
    return payload;
  }

  Future<void> sendPhoneOtp(
    String phone, {
    bool register = false,
    String? fullName,
    String? city,
  }) async {
    if (normalizePhone(phone) != phone) {
      throw const DriverAuthException(
        'Enter a valid mobile number with country code.',
      );
    }
    if (register && (fullName == null || fullName.trim().length < 2)) {
      throw const DriverAuthException('Enter your full name.');
    }
    await _request(
      'otp',
      body: {
        'phone': phone,
        'channel': 'sms',
        'create_user': register,
        if (register)
          'data': {
            'full_name': fullName!.trim(),
            if (city != null && city.trim().isNotEmpty) 'city': city.trim(),
            // Contact/onboarding metadata only; never used for authorization.
            'onboarding_intent': 'driver',
          },
      },
    );
  }

  Future<IdentitySession> verifyPhoneOtp(String phone, String code) async {
    if (normalizePhone(phone) != phone || !isValidOtp(code)) {
      throw const DriverAuthException(
        'Enter the 6-digit code sent to your mobile.',
      );
    }
    return IdentitySession.fromJson(
      await _request(
        'verify',
        body: {'phone': phone, 'token': code.trim(), 'type': 'sms'},
      ),
    );
  }

  Future<IdentitySession?> signInWithGoogle() async {
    requireConfigured();
    final tokens = await (googleTokenProvider ?? _nativeGoogleTokens)();
    if (tokens == null) return null; // The driver closed the account chooser.
    if (tokens.idToken.isEmpty || tokens.accessToken.isEmpty) {
      throw const DriverAuthException(
        'Google could not verify your account. Please try again.',
      );
    }
    return IdentitySession.fromJson(
      await _request(
        'token?grant_type=id_token',
        body: {
          'provider': 'google',
          'id_token': tokens.idToken,
          'access_token': tokens.accessToken,
        },
      ),
    );
  }

  Future<GoogleIdentityTokens?> _nativeGoogleTokens() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      throw const DriverAuthException(
        'Use Google sign-in in the Android or iPhone app.',
      );
    }
    if (config.googleWebClientId.isEmpty) {
      throw const DriverAuthException(
        'Google sign-in is being set up. Please contact HireD support.',
      );
    }
    final google = GoogleSignIn.instance;
    try {
      // google_sign_in 7 requires exactly one initialization per app process.
      await (_googleInitialization ??= google.initialize(
        clientId:
            defaultTargetPlatform == TargetPlatform.iOS &&
                config.googleIosClientId.isNotEmpty
            ? config.googleIosClientId
            : null,
        serverClientId: config.googleWebClientId,
      ));
      final account = await google.authenticate();
      const scopes = ['email', 'profile'];
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const DriverAuthException(
          'Google could not verify your account. Please try again.',
        );
      }
      return GoogleIdentityTokens(idToken, authorization.accessToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw const DriverAuthException(
        'Google sign-in could not finish. Please try again or use your mobile number.',
      );
    }
  }

  Future<void> signOut(String accessToken) async {
    await _request('logout?scope=local', body: {}, bearer: accessToken);
  }
}
