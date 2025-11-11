import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:domail/constants/app_constants.dart';
import 'package:domail/config/oauth_config.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:window_to_front/window_to_front.dart';

class GoogleAuthService {
  static const _prefsKeyAccounts = 'accounts_json';
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;
  GoogleAuthService._internal();

  // Lazy-initialize GoogleSignIn only when needed to prevent automatic sign-in attempts
  GoogleSignIn? _googleSignIn;
  GoogleSignIn get _googleSignInInstance {
    _googleSignIn ??= GoogleSignIn(
      scopes: <String>[
        'email',
        'https://www.googleapis.com/auth/gmail.readonly',
        'https://www.googleapis.com/auth/gmail.modify',
        'https://www.googleapis.com/auth/userinfo.profile',
      ],
      // Prevent automatic sign-in attempts that can trigger chooser unexpectedly
      signInOption: SignInOption.standard,
      // Don't request server auth code (we handle OAuth manually)
      serverClientId: null,
    );
    return _googleSignIn!;
  }

  // Cache for ongoing ensureValidAccessToken calls to prevent duplicate checks
  final Map<String, Future<GoogleAccount?>> _tokenCheckCache = {};
  // Cache for ongoing refreshAccessToken calls to prevent duplicate refreshes
  final Map<String, Future<GoogleAccount?>> _refreshTokenCache = {};
  // Prevent parallel/duplicate interactive sign-ins
  Future<GoogleAccount?>? _signInInProgress;

  Future<List<GoogleAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_prefsKeyAccounts);
    if (jsonStr == null || jsonStr.isEmpty) return [];
    final List<dynamic> list = jsonDecode(jsonStr);
    return list.map((e) => GoogleAccount.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveAccounts(List<GoogleAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyAccounts, jsonEncode(accounts.map((e) => e.toJson()).toList()));
  }

  /// Upsert an account by email; if email exists, update tokens on existing entry and keep its id
  Future<GoogleAccount> upsertAccount(GoogleAccount account) async {
    final list = await loadAccounts();
    final idx = list.indexWhere((a) => a.email.toLowerCase() == account.email.toLowerCase());
    if (idx != -1) {
      final existing = list[idx];
      final updated = existing.copyWith(
        accessToken: account.accessToken,
        refreshToken: account.refreshToken ?? existing.refreshToken,
        tokenExpiryMs: account.tokenExpiryMs ?? existing.tokenExpiryMs,
      );
      list[idx] = updated;
      await saveAccounts(list);
      return updated;
    } else {
      final updated = account;
      await saveAccounts([...list, updated]);
      return updated;
    }
  }

  Future<GoogleAccount?> getAccountById(String id) async {
    final list = await loadAccounts();
    try {
      return list.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<GoogleAccount?> signIn() async {
    if (_signInInProgress != null) return _signInInProgress;
    final future = _signInDo();
    _signInInProgress = future;
    try {
      final result = await future;
      return result;
    } finally {
      _signInInProgress = null;
    }
  }

  Future<GoogleAccount?> _signInDo() async {
    // Desktop Windows/Linux: use flutter_web_auth_2 with PKCE and installed redirect
    if (Platform.isWindows || Platform.isLinux) {
      try {
        final verifier = _randomString(64);
        final challenge = _codeChallenge(verifier);
        final redirect = Uri.parse(AppConstants.oauthRedirectUri);
        final redirectUri = AppConstants.oauthRedirectUri;
        // Debug logging
        // ignore: avoid_print
        print('[auth][desktop] using redirect_uri=$redirectUri');
        // ignore: avoid_print
        print('[auth][desktop] using client_id=${OAuthConfig.clientId}');
        // Use 'consent' to force consent screen and ensure refresh token is returned
        // This is necessary because Google only returns refresh_token on first authorization
        // or when consent is explicitly requested
        final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': OAuthConfig.clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': AppConstants.oauthScopes.join(' '),
          'prompt': 'consent',  // Force consent to get refresh token
          'access_type': 'offline',
          'include_granted_scopes': 'true',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
        }).toString();
        // Launch default browser and capture redirect via local loopback listener
        final port = redirect.port == 0 ? 8400 : redirect.port;
        final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
        final request = await listener.first;
        final uri = request.uri;
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        final errorDescription = uri.queryParameters['error_description'];
        
        if (error != null) {
          // ignore: avoid_print
          print('[auth] OAuth error from Google: $error - $errorDescription');
        }
        // Respond to close the tab
        request.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/html')
          ..write('<html><body><p>Authentication complete. You can close this window.</p></body></html>');
        await request.response.close();
        await listener.close(force: true);
        if (code == null) return null;
        // Exchange code
        final resp = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': OAuthConfig.clientId,
            'redirect_uri': AppConstants.oauthRedirectUri,
            'grant_type': 'authorization_code',
            'code': code,
            'code_verifier': verifier,
            'client_secret': OAuthConfig.clientSecret,
          },
        );
        if (resp.statusCode != 200) {
          // Log error for debugging
          // ignore: avoid_print
          print('[auth] token exchange failed: status=${resp.statusCode} body=${resp.body}');
          return null;
        }
        final tok = jsonDecode(resp.body) as Map<String, dynamic>;
        final accessToken = tok['access_token'] as String? ?? '';
        final refreshToken = tok['refresh_token'] as String?; // may be null if previously granted
        final expiresIn = (tok['expires_in'] as num?)?.toInt();
        final idToken = tok['id_token'] as String? ?? '';
        String displayName = 'Google Account';
        String email = 'unknown@email';
        String? photoUrl;
        if (accessToken.isNotEmpty) {
          final ui = await http.get(
            Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
            headers: {'Authorization': 'Bearer $accessToken'},
          );
          if (ui.statusCode == 200) {
            final data = jsonDecode(ui.body) as Map<String, dynamic>;
            email = (data['email'] as String?) ?? email;
            displayName = (data['name'] as String?) ?? displayName;
            photoUrl = data['picture'] as String?;
          }
        }
        final account = GoogleAccount(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
          accessToken: accessToken,
          refreshToken: refreshToken,
          tokenExpiryMs: expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch : null,
          idToken: idToken,
        );
        // Bring window to front after successful sign-in
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          try {
            await WindowToFront.activate();
          } catch (_) {
            // Ignore if it fails
          }
        }
        return account;
      } catch (_) {
        // continue
      }
    }
    // Use PKCE (code) flow for mobile
    if (OAuthConfig.clientId.isNotEmpty && (Platform.isAndroid || Platform.isIOS)) {
      try {
        // Android: Launch browser directly and handle HTTPS App Links manually
        // App Links auto-open app without chooser when domain is verified
        if (Platform.isAndroid) {
          final redirectUri = AppConstants.oauthRedirectUriForMobile;
          final verifier = _randomString(64);
          final challenge = _codeChallenge(verifier);
          
          final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
            'client_id': OAuthConfig.clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': AppConstants.oauthScopes.join(' '),
            'prompt': 'consent',
            'access_type': 'offline',
            'include_granted_scopes': 'true',
            'code_challenge': challenge,
            'code_challenge_method': 'S256',
          });
          
          // Debug the exact auth request
          // ignore: avoid_print
          print('[auth][android] launching browser with redirect_uri=$redirectUri');
          // ignore: avoid_print
          print('[auth][android] full auth URL: $authUrl');
          // ignore: avoid_print
          print('[auth][android] client_id: ${OAuthConfig.clientId}');
          
          // Check for initial App Link (in case app was restarted)
          final methodChannel = MethodChannel('com.seagreen.domail/bringToFront');
          String? callbackUrl;
          
          try {
            // ignore: avoid_print
            print('[auth][android] checking for initial app link...');
            final initialLink = await methodChannel.invokeMethod<String>('getInitialAppLink');
            // ignore: avoid_print
            print('[auth][android] getInitialAppLink returned: $initialLink');
            if (initialLink != null && initialLink.isNotEmpty) {
              callbackUrl = initialLink;
              // ignore: avoid_print
              print('[auth][android] got initial app link: $callbackUrl');
            }
          } catch (e) {
            // ignore: avoid_print
            print('[auth][android] no initial link (expected on first launch): $e');
          }
          
          // If we have initial link, check if it has matching OAuth state
          if (callbackUrl != null) {
            // ignore: avoid_print
            print('[auth][android] found initial App Link, checking for OAuth state...');
            final callbackUri = Uri.parse(callbackUrl);
            final code = callbackUri.queryParameters['code'];
            final error = callbackUri.queryParameters['error'];
            
            if (error != null) {
              // ignore: avoid_print
              print('[auth][android] OAuth error in App Link: $error');
              // Clear the intent data so it doesn't get reused
              await methodChannel.invokeMethod('clearAppLink');
              return null;
            }
            
            if (code == null) {
              // ignore: avoid_print
              print('[auth][android] No code in App Link');
              await methodChannel.invokeMethod('clearAppLink');
              return null;
            }
            
            // Get stored OAuth state
            final prefs = await SharedPreferences.getInstance();
            final storedVerifier = prefs.getString('oauth_pkce_verifier');
            final storedRedirectUri = prefs.getString('oauth_redirect_uri');
            final storedClientId = prefs.getString('oauth_client_id');
            final storedClientSecret = prefs.getString('oauth_client_secret');
            
            if (storedVerifier != null && storedRedirectUri != null && storedClientId != null && storedClientSecret != null) {
              // ignore: avoid_print
              print('[auth][android] OAuth state found, completing sign-in...');
              // Clear stored state
              await prefs.remove('oauth_pkce_verifier');
              await prefs.remove('oauth_redirect_uri');
              await prefs.remove('oauth_client_id');
              await prefs.remove('oauth_client_secret');
              
              // Clear the intent data
              await methodChannel.invokeMethod('clearAppLink');
              
              // Complete OAuth flow
              return await completeOAuthFlow(code, storedVerifier, storedRedirectUri, storedClientId, storedClientSecret);
            } else {
              // ignore: avoid_print
              print('[auth][android] OAuth state missing - this App Link is from a previous attempt');
              // Clear the intent data so it doesn't interfere with new sign-in
              await methodChannel.invokeMethod('clearAppLink');
              // Continue with normal flow (launch browser)
              callbackUrl = null;
            }
          }
          
          // No initial link - store OAuth state and launch browser
          // App will restart when Google redirects, and splash screen will complete sign-in
          // ignore: avoid_print
          print('[auth][android] storing OAuth state and launching browser...');
          
          // Store OAuth state for when app restarts
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('oauth_pkce_verifier', verifier);
          await prefs.setString('oauth_redirect_uri', redirectUri);
          await prefs.setString('oauth_client_id', OAuthConfig.clientId);
          await prefs.setString('oauth_client_secret', OAuthConfig.clientSecret);
          
          // Launch browser - app will restart when Google redirects
          final launched = await launchUrl(authUrl, mode: LaunchMode.externalApplication);
          // ignore: avoid_print
          print('[auth][android] browser launched: $launched');
          
          // Return null - splash screen will detect App Link on restart and complete sign-in
          return null;
        } else {
          // iOS: Use flutter_web_auth_2 with custom scheme
          final redirectUri = AppConstants.oauthRedirectUriForMobile;
          final callbackUrlScheme = redirectUri.split(':/').first;
          
          final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
            'client_id': OAuthConfig.clientId,
            'redirect_uri': redirectUri,
            'response_type': 'code',
            'scope': AppConstants.oauthScopes.join(' '),
            'prompt': 'consent',
            'access_type': 'offline',
            'include_granted_scopes': 'true',
          });
          
          final callbackUrl = await FlutterWebAuth2.authenticate(
            url: authUrl.toString(),
            callbackUrlScheme: callbackUrlScheme,
          );
          
          final callbackUri = Uri.parse(callbackUrl);
          final code = callbackUri.queryParameters['code'];
          if (code == null) return null;
          
          // Exchange code for tokens (same as above)
          final resp = await http.post(
            Uri.parse('https://oauth2.googleapis.com/token'),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {
              'client_id': OAuthConfig.clientId,
              'redirect_uri': redirectUri,
              'grant_type': 'authorization_code',
              'code': code,
              'client_secret': OAuthConfig.clientSecret,
            },
          );
          
          if (resp.statusCode != 200) return null;
          final tok = jsonDecode(resp.body) as Map<String, dynamic>;
          final accessToken = tok['access_token'] as String? ?? '';
          final refreshToken = tok['refresh_token'] as String?;
          final expiresIn = (tok['expires_in'] as num?)?.toInt();
          final idToken = tok['id_token'] as String? ?? '';
          
          // Fetch user info
          String displayName = 'Google Account';
          String email = 'unknown@email';
          String? photoUrl;
          if (accessToken.isNotEmpty) {
            final ui = await http.get(
              Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
              headers: {'Authorization': 'Bearer $accessToken'},
            );
            if (ui.statusCode == 200) {
              final data = jsonDecode(ui.body) as Map<String, dynamic>;
              email = (data['email'] as String?) ?? email;
              displayName = (data['name'] as String?) ?? displayName;
              photoUrl = data['picture'] as String?;
            }
          }
          
          final account = GoogleAccount(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            email: email,
            displayName: displayName,
            photoUrl: photoUrl,
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenExpiryMs: expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch : null,
            idToken: idToken,
          );
          // Bring window to front after successful sign-in (for desktop)
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            try {
              await WindowToFront.activate();
            } catch (_) {
              // Ignore if it fails
            }
          }
          return account;
        }
      } catch (_) {
        // continue to fallback
      }
    }
    
    // Fallback: Use flutter_appauth for iOS or if web_auth_2 fails
    if (OAuthConfig.clientId.isNotEmpty) {
      try {
        final appAuth = const FlutterAppAuth();
        final redirectUri = Platform.isIOS 
            ? AppConstants.oauthRedirectUriForMobile
            : AppConstants.oauthRedirectUri;
        final result = await appAuth.authorizeAndExchangeCode(
          AuthorizationTokenRequest(
            OAuthConfig.clientId,
            redirectUri,
            scopes: AppConstants.oauthScopes,
            serviceConfiguration: const AuthorizationServiceConfiguration(
              authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
              tokenEndpoint: 'https://oauth2.googleapis.com/token',
            ),
            promptValues: ['select_account'],
            additionalParameters: {
              'access_type': 'offline',
              'include_granted_scopes': 'true',
            },
          ),
        );
        if (result == null) return null;
        String displayName = 'Google Account';
        String email = 'unknown@email';
        String? photoUrl;
        // Fetch basic profile
        if (result.accessToken != null && result.accessToken!.isNotEmpty) {
          final resp = await http.get(
            Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
            headers: {'Authorization': 'Bearer ${result.accessToken}'},
          );
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body) as Map<String, dynamic>;
            email = (data['email'] as String?) ?? email;
            displayName = (data['name'] as String?) ?? displayName;
            photoUrl = data['picture'] as String?;
          }
        }
        final account = GoogleAccount(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          email: email,
          displayName: displayName,
          photoUrl: photoUrl,
          accessToken: result.accessToken ?? '',
          refreshToken: result.refreshToken,
          tokenExpiryMs: result.accessTokenExpirationDateTime?.millisecondsSinceEpoch,
          idToken: result.idToken ?? '',
        );
        // Bring window to front after successful sign-in (for desktop)
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          try {
            await WindowToFront.activate();
          } catch (_) {
            // Ignore if it fails
          }
        }
        return account;
      } catch (_) {
        // fall through to google_sign_in if available
      }
    }
    // Fallback to google_sign_in where supported
    if (kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final account = await _googleSignInInstance.signIn();
      if (account == null) return null;
      final auth = await account.authentication;
      final googleAccount = GoogleAccount(
        id: account.id,
        email: account.email,
        displayName: account.displayName ?? account.email,
        photoUrl: account.photoUrl,
        accessToken: auth.accessToken ?? '',
        refreshToken: null,
        tokenExpiryMs: null,
        idToken: auth.idToken ?? '',
      );
      // Bring window to front after successful sign-in (for desktop)
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        try {
          await WindowToFront.activate();
        } catch (_) {
          // Ignore if it fails
        }
      }
      return googleAccount;
    }
    return null;
  }

  Future<void> signOutAll() async {
    await _googleSignInInstance.disconnect();
  }

  Future<bool> signOutAccount(String accountId) async {
    final list = await loadAccounts();
    final idx = list.indexWhere((a) => a.id == accountId);
    if (idx == -1) return false;
    final updated = list[idx].copyWith(accessToken: '', tokenExpiryMs: null);
    list[idx] = updated;
    await saveAccounts(list);
    return true;
  }

  Future<bool> removeAccount(String accountId) async {
    final list = await loadAccounts();
    final filtered = list.where((a) => a.id != accountId).toList();
    await saveAccounts(filtered);
    return filtered.length != list.length;
  }

  /// Ensure the account has a valid (non-expired) access token.
  /// If near expiry or invalid per tokeninfo, refresh using refresh_token.
  /// Uses a cache to prevent duplicate simultaneous calls for the same account.
  Future<GoogleAccount?> ensureValidAccessToken(String accountId) async {
    // Use putIfAbsent for atomic check-and-set to prevent race conditions
    return _tokenCheckCache.putIfAbsent(accountId, () {
      // Create the future for this check
      final future = _performTokenCheck(accountId);

      // Remove from cache when done (success or failure)
      future.then((_) {
        _tokenCheckCache.remove(accountId);
      }).catchError((_) {
        _tokenCheckCache.remove(accountId);
      });

      return future;
    });
  }

  Future<GoogleAccount?> _performTokenCheck(String accountId) async {
    var account = await getAccountById(accountId);
    if (account == null) return null;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isNearExpiry = (account.tokenExpiryMs != null) && (account.tokenExpiryMs! <= nowMs + 60000);
    bool valid = false;
    if (!isNearExpiry && account.accessToken.isNotEmpty) {
      valid = await _isAccessTokenValid(account.accessToken);
    }
    // Debug current token state
    final remainingMs = account.tokenExpiryMs != null ? (account.tokenExpiryMs! - nowMs) : null;
    // ignore: avoid_print
    print('[auth] ensureValidAccessToken account=$accountId access=${account.accessToken.isNotEmpty} refresh=${(account.refreshToken ?? '').isNotEmpty} nearExpiry=$isNearExpiry remainingMs=${remainingMs ?? -1} valid=$valid');
    if (isNearExpiry || !valid) {
      // Check if refresh token exists
      if (account.refreshToken == null || account.refreshToken!.isEmpty) {
        // ignore: avoid_print
        print('[auth] no refreshToken available, account needs re-authentication account=$accountId');
        // Return null to indicate authentication is required
        // The caller should handle this by prompting for re-authentication
        return null;
      }
      
      final refreshed = await refreshAccessToken(accountId);
      if (refreshed != null && refreshed.accessToken.isNotEmpty) {
        account = refreshed;
        final rem2 = account.tokenExpiryMs != null ? (account.tokenExpiryMs! - DateTime.now().millisecondsSinceEpoch) : null;
        // ignore: avoid_print
        print('[auth] refreshed access token account=$accountId ok remainingMs=${rem2 ?? -1}');
      } else {
        // ignore: avoid_print
        print('[auth] refresh failed account=$accountId - token refresh request failed');
        // Refresh failed - return null to indicate re-authentication needed
        return null;
      }
    }
    return account;
  }

  Future<bool> _isAccessTokenValid(String accessToken) async {
    try {
      final resp = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=$accessToken'),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // Interactive re-auth to obtain a fresh access/refresh token and persist it for an existing account
  Future<GoogleAccount?> reauthenticateAccount(String accountId) async {
    // Desktop flow similar to signIn, but force consent to obtain refresh_token
    if (Platform.isWindows || Platform.isLinux) {
      try {
        final verifier = _randomString(64);
        final challenge = _codeChallenge(verifier);
        final redirect = Uri.parse(AppConstants.oauthRedirectUri);
        final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
          'client_id': OAuthConfig.clientId,
          'redirect_uri': AppConstants.oauthRedirectUri,
          'response_type': 'code',
          'scope': AppConstants.oauthScopes.join(' '),
          'prompt': 'consent',
          'access_type': 'offline',
          'include_granted_scopes': 'true',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
        }).toString();
        final port = redirect.port == 0 ? 8400 : redirect.port;
        final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);
        final request = await listener.first;
        final uri = request.uri;
        final code = uri.queryParameters['code'];
        request.response
          ..statusCode = 200
          ..headers.set('Content-Type', 'text/html')
          ..write('<html><body><p>Authentication complete. You can close this window.</p></body></html>');
        await request.response.close();
        await listener.close(force: true);
        if (code == null) return null;
        final resp = await http.post(
          Uri.parse('https://oauth2.googleapis.com/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {
            'client_id': OAuthConfig.clientId,
            'redirect_uri': AppConstants.oauthRedirectUri,
            'grant_type': 'authorization_code',
            'code': code,
            'code_verifier': verifier,
            'client_secret': OAuthConfig.clientSecret,
          },
        );
        if (resp.statusCode != 200) return null;
        final tok = jsonDecode(resp.body) as Map<String, dynamic>;
        final accessToken = tok['access_token'] as String? ?? '';
        final refreshToken = tok['refresh_token'] as String?;
        final expiresIn = (tok['expires_in'] as num?)?.toInt();

        // Fetch user info and update existing account (no longer needed as email is not used)
        final list = await loadAccounts();
        final idx = list.indexWhere((a) => a.id == accountId);
        if (idx == -1) return null;
        final updated = list[idx].copyWith(
          accessToken: accessToken,
          refreshToken: refreshToken ?? list[idx].refreshToken,
          tokenExpiryMs: expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch : list[idx].tokenExpiryMs,
        );
        list[idx] = updated;
        await saveAccounts(list);
        return updated;
      } catch (_) {
        return null;
      }
    }
    // Mobile/appauth: force consent to ensure refresh_token
    try {
      final appAuth = const FlutterAppAuth();
      // Use mobile-specific redirect URI for Android/iOS
      final redirectUri = Platform.isAndroid || Platform.isIOS 
          ? AppConstants.oauthRedirectUriForMobile
          : AppConstants.oauthRedirectUri;
      final result = await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          OAuthConfig.clientId,
          redirectUri,
          scopes: AppConstants.oauthScopes,
          serviceConfiguration: const AuthorizationServiceConfiguration(
            authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
            tokenEndpoint: 'https://oauth2.googleapis.com/token',
          ),
          promptValues: ['consent', 'select_account'],
          additionalParameters: {
            'access_type': 'offline',
            'include_granted_scopes': 'true',
          },
        ),
      );
      if (result == null) return null;
      final list = await loadAccounts();
      final idx = list.indexWhere((a) => a.id == accountId);
      if (idx == -1) return null;
      final updated = list[idx].copyWith(
        accessToken: result.accessToken ?? list[idx].accessToken,
        refreshToken: result.refreshToken ?? list[idx].refreshToken,
        tokenExpiryMs: result.accessTokenExpirationDateTime?.millisecondsSinceEpoch ?? list[idx].tokenExpiryMs,
      );
      list[idx] = updated;
      await saveAccounts(list);
      return updated;
    } catch (_) {
      return null;
    }
  }

  /// Complete OAuth flow by exchanging code for tokens and fetching user info
  /// Used when app restarts via App Link after browser OAuth
  Future<GoogleAccount?> completeOAuthFlow(
    String code,
    String verifier,
    String redirectUri,
    String clientId,
    String clientSecret,
  ) async {
    // Exchange code for tokens
    final resp = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'client_secret': clientSecret,
      },
    );
    
    if (resp.statusCode != 200) {
      // ignore: avoid_print
      print('[auth] token exchange failed: ${resp.statusCode} ${resp.body}');
      return null;
    }
    
    final tok = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = tok['access_token'] as String? ?? '';
    final refreshToken = tok['refresh_token'] as String?;
    final expiresIn = (tok['expires_in'] as num?)?.toInt();
    final idToken = tok['id_token'] as String? ?? '';
    
    // Fetch user info
    String displayName = 'Google Account';
    String email = 'unknown@email';
    String? photoUrl;
    if (accessToken.isNotEmpty) {
      final ui = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (ui.statusCode == 200) {
        final data = jsonDecode(ui.body) as Map<String, dynamic>;
        email = (data['email'] as String?) ?? email;
        displayName = (data['name'] as String?) ?? displayName;
        photoUrl = data['picture'] as String?;
      }
    }
    
    return GoogleAccount(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenExpiryMs: expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch : null,
      idToken: idToken,
    );
  }

  Future<GoogleAccount?> refreshAccessToken(String accountId) async {
    // Use putIfAbsent for atomic check-and-set to prevent concurrent refresh attempts
    return _refreshTokenCache.putIfAbsent(accountId, () {
      final future = _performTokenRefresh(accountId);

      // Remove from cache when done (success or failure)
      future.then((_) {
        _refreshTokenCache.remove(accountId);
      }).catchError((_) {
        _refreshTokenCache.remove(accountId);
      });

      return future;
    });
  }

  Future<GoogleAccount?> _performTokenRefresh(String accountId) async {
    final account = await getAccountById(accountId);
    if (account == null || account.refreshToken == null || account.refreshToken!.isEmpty) return null;
    final resp = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': OAuthConfig.clientId,
        'client_secret': OAuthConfig.clientSecret,
        'grant_type': 'refresh_token',
        'refresh_token': account.refreshToken!,
      },
    );
    if (resp.statusCode != 200) {
      // Log error details for debugging
      // ignore: avoid_print
      print('[auth] refresh token request failed: status=${resp.statusCode} body=${resp.body}');
      return null;
    }
    final tok = jsonDecode(resp.body) as Map<String, dynamic>;
    final accessToken = tok['access_token'] as String?;
    final expiresIn = (tok['expires_in'] as num?)?.toInt();
    if (accessToken == null || accessToken.isEmpty) {
      // ignore: avoid_print
      print('[auth] refresh token response missing access_token: $tok');
      return null;
    }
    final updated = account.copyWith(
      accessToken: accessToken,
      tokenExpiryMs: expiresIn != null ? DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch : account.tokenExpiryMs,
    );
    final list = await loadAccounts();
    final idx = list.indexWhere((a) => a.id == account.id);
    if (idx != -1) {
      list[idx] = updated;
      await saveAccounts(list);
    }
    return updated;
  }
}

@immutable
class GoogleAccount {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String accessToken;
  final String? refreshToken;
  final int? tokenExpiryMs;
  final String idToken;

  const GoogleAccount({
    required this.id,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.tokenExpiryMs,
    required this.idToken,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'tokenExpiryMs': tokenExpiryMs,
        'idToken': idToken,
      };

  factory GoogleAccount.fromJson(Map<String, dynamic> json) => GoogleAccount(
        id: json['id'] as String,
        email: json['email'] as String,
        displayName: json['displayName'] as String,
        photoUrl: json['photoUrl'] as String?,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String?,
        tokenExpiryMs: json['tokenExpiryMs'] as int?,
        idToken: json['idToken'] as String,
      );

  GoogleAccount copyWith({
    String? accessToken,
    String? refreshToken,
    int? tokenExpiryMs,
  }) {
    return GoogleAccount(
      id: id,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiryMs: tokenExpiryMs ?? this.tokenExpiryMs,
      idToken: idToken,
    );
  }
}

String _randomString(int length) {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
  final rnd = Random.secure();
  return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
}

String _codeChallenge(String verifier) {
  final bytes = utf8.encode(verifier);
  final digest = crypto.sha256.convert(bytes);
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}


