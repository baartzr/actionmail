import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:domail/services/auth/google_auth_service.dart';
import 'package:domail/shared/widgets/app_window_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:domail/constants/app_brand.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with WidgetsBindingObserver {
  List<GoogleAccount> _accounts = [];
  bool _signingIn = false;
  bool _forceAdd = false;
  bool _dialogShown = false;
  bool _navigatedAway = false; // Track if we've already navigated away
  String? _processedAppLink; // Track which App Link we've already processed

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAppLinkAndCompleteSignIn();
    _load();
    // No longer resize native window; open add-account as modal instead
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Check for App Link when app resumes from background (after browser OAuth)
    if (state == AppLifecycleState.resumed && Platform.isAndroid) {
      // ignore: avoid_print
      print('[splash] app resumed, checking for App Link...');
      _checkAppLinkAndCompleteSignIn();
    }
  }

  Future<void> _checkAppLinkAndCompleteSignIn() async {
    if (!Platform.isAndroid) return;
    
    // ignore: avoid_print
    print('[splash] _checkAppLinkAndCompleteSignIn() called');
    
    try {
      final methodChannel = MethodChannel('com.seagreen.domail/bringToFront');
      // ignore: avoid_print
      print('[splash] calling getInitialAppLink...');
      final appLink = await methodChannel.invokeMethod<String>('getInitialAppLink');
      // ignore: avoid_print
      print('[splash] getInitialAppLink returned: $appLink');
      
      if (appLink != null && appLink.isNotEmpty && appLink.contains('code=')) {
        // Check if we've already processed this App Link
        if (_processedAppLink == appLink) {
          // ignore: avoid_print
          print('[splash] App Link already processed, skipping: $appLink');
          return;
        }
        
        // App was opened via OAuth redirect - complete sign-in
        // ignore: avoid_print
        print('[splash] detected OAuth App Link on startup: $appLink');
        
        // Extract code from URL
        final uri = Uri.parse(appLink);
        final code = uri.queryParameters['code'];
        final error = uri.queryParameters['error'];
        
        if (error != null) {
          // ignore: avoid_print
          print('[splash] OAuth error in App Link: $error');
          _processedAppLink = appLink; // Mark as processed even on error
          return;
        }
        
        if (code != null) {
          // Check if we've already processed this exact App Link
          if (_processedAppLink == appLink) {
            // ignore: avoid_print
            print('[splash] App Link already processed, skipping');
            return;
          }
          
          // We need to get the verifier from SharedPreferences (stored before browser launch)
          final prefs = await SharedPreferences.getInstance();
          final verifier = prefs.getString('oauth_pkce_verifier');
          final redirectUri = prefs.getString('oauth_redirect_uri');
          final clientId = prefs.getString('oauth_client_id');
          final clientSecret = prefs.getString('oauth_client_secret');
          
          if (verifier != null && redirectUri != null && clientId != null && clientSecret != null) {
            // Mark as processing to prevent duplicate
            _processedAppLink = appLink;
            
            // Check if this is a re-authentication
            final reauthAccountId = prefs.getString('oauth_reauth_account_id');
            final isReauth = reauthAccountId != null && reauthAccountId.isNotEmpty;
            
            // ignore: avoid_print
            print('[splash] completing OAuth with stored verifier, isReauth=$isReauth accountId=$reauthAccountId');
            
            // Exchange code for tokens
            final svc = GoogleAuthService();
            // ignore: avoid_print
            print('[splash] Calling completeOAuthFlow for ${isReauth ? "re-auth" : "sign-in"}...');
            final account = await svc.completeOAuthFlow(code, verifier, redirectUri, clientId, clientSecret);
            
            if (account == null) {
              // ignore: avoid_print
              print('[splash] completeOAuthFlow returned null - token exchange may have failed');
              // Clear stored OAuth state on failure
              await prefs.remove('oauth_pkce_verifier');
              await prefs.remove('oauth_redirect_uri');
              await prefs.remove('oauth_client_id');
              await prefs.remove('oauth_client_secret');
              await prefs.remove('oauth_reauth_account_id');
              _processedAppLink = null;
              return;
            }
            
            // ignore: avoid_print
            print('[splash] completeOAuthFlow succeeded, got tokens: accessToken=${account.accessToken.isNotEmpty ? '${account.accessToken.substring(0, 20)}...' : 'EMPTY'} refreshToken=${account.refreshToken != null && account.refreshToken!.isNotEmpty ? '${account.refreshToken!.substring(0, 20)}...' : 'null/empty'} tokenExpiryMs=${account.tokenExpiryMs}');
            
            // Clear stored OAuth state
            await prefs.remove('oauth_pkce_verifier');
            await prefs.remove('oauth_redirect_uri');
            await prefs.remove('oauth_client_id');
            await prefs.remove('oauth_client_secret');
            await prefs.remove('oauth_reauth_account_id');
            
            if (mounted) {
              if (isReauth) {
                // Re-authentication: Update existing account
                // ignore: avoid_print
                print('[splash] OAuth re-auth completed, updating account $reauthAccountId');
                final existingAccounts = await svc.loadAccounts();
                // ignore: avoid_print
                print('[splash] Found ${existingAccounts.length} existing accounts');
                final idx = existingAccounts.indexWhere((a) => a.id == reauthAccountId);
                if (idx != -1) {
                  // Update existing account with new tokens
                  final existingAccount = existingAccounts[idx];
                  // ignore: avoid_print
                  print('[splash] Before update - existing account: accessToken=${existingAccount.accessToken.isNotEmpty ? '${existingAccount.accessToken.substring(0, 20)}...' : 'EMPTY'} refreshToken=${existingAccount.refreshToken != null && existingAccount.refreshToken!.isNotEmpty ? '${existingAccount.refreshToken!.substring(0, 20)}...' : 'null/empty'} tokenExpiryMs=${existingAccount.tokenExpiryMs}');
                  
                  final updated = existingAccount.copyWith(
                    accessToken: account.accessToken,
                    refreshToken: account.refreshToken ?? existingAccount.refreshToken,
                    tokenExpiryMs: account.tokenExpiryMs,
                  );
                  // ignore: avoid_print
                  print('[splash] After copyWith - updated account: accessToken=${updated.accessToken.isNotEmpty ? '${updated.accessToken.substring(0, 20)}...' : 'EMPTY'} refreshToken=${updated.refreshToken != null && updated.refreshToken!.isNotEmpty ? '${updated.refreshToken!.substring(0, 20)}...' : 'null/empty'} tokenExpiryMs=${updated.tokenExpiryMs}');
                  
                  existingAccounts[idx] = updated;
                  await svc.saveAccounts(existingAccounts);
                  // ignore: avoid_print
                  print('[splash] Accounts saved to SharedPreferences');
                  
                  // Verify what was saved by reloading
                  final verifyAccounts = await svc.loadAccounts();
                  final verifyIdx = verifyAccounts.indexWhere((a) => a.id == reauthAccountId);
                  if (verifyIdx != -1) {
                    final verifyAccount = verifyAccounts[verifyIdx];
                    // ignore: avoid_print
                    print('[splash] Verification after save - loaded account: accessToken=${verifyAccount.accessToken.isNotEmpty ? '${verifyAccount.accessToken.substring(0, 20)}...' : 'EMPTY'} refreshToken=${verifyAccount.refreshToken != null && verifyAccount.refreshToken!.isNotEmpty ? '${verifyAccount.refreshToken!.substring(0, 20)}...' : 'null/empty'} tokenExpiryMs=${verifyAccount.tokenExpiryMs}');
                  } else {
                    // ignore: avoid_print
                    print('[splash] ERROR: Account not found after save! accountId=$reauthAccountId');
                  }
                  
                  // Clear token check cache since tokens were updated
                  svc.clearTokenCheckCache(reauthAccountId);
                  // ignore: avoid_print
                  print('[splash] Token check cache cleared for account $reauthAccountId');
                  
                  // Clear error state
                  svc.clearLastError(reauthAccountId);
                  // Mark as recently re-authenticated to prevent immediate callback trigger
                  await prefs.setBool('oauth_recently_reauthd_$reauthAccountId', true);
                  // Clear the flag after 5 seconds (enough time for app to resume and check tokens)
                  Future.delayed(const Duration(seconds: 5), () async {
                    await prefs.remove('oauth_recently_reauthd_$reauthAccountId');
                  });
                  // ignore: avoid_print
                  print('[splash] Re-auth successful, tokens updated for account $reauthAccountId: accessToken=${updated.accessToken.isNotEmpty} refreshToken=${updated.refreshToken != null && updated.refreshToken!.isNotEmpty} tokenExpiryMs=${updated.tokenExpiryMs}');
                } else {
                  // ignore: avoid_print
                  print('[splash] Re-auth account not found: $reauthAccountId');
                  print('[splash] Available account IDs: ${existingAccounts.map((a) => a.id).join(", ")}');
                }
              } else {
                // New sign-in: Create new account
                // ignore: avoid_print
                print('[splash] OAuth completed, saving new account');
                final stored = await svc.upsertAccount(account);
                await _saveLastActiveAccount(stored.id);
              }
              
              // Clear the App Link from intent after successful processing
              try {
                await methodChannel.invokeMethod('clearAppLink');
              } catch (_) {
                // Ignore if method not available
              }
              
              if (mounted) {
                // Navigate to home - use reauthAccountId if re-auth, otherwise use new account id
                final targetAccountId = isReauth ? reauthAccountId : (await svc.loadAccounts()).firstWhere((a) => a.id == account.id, orElse: () => account).id;
                // ignore: avoid_print
                print('[splash] navigating to home with account $targetAccountId');
                _navigatedAway = true; // Mark as navigated to prevent pop attempts
                // Use pushReplacementNamed to avoid Navigator history issues
                Navigator.of(context, rootNavigator: true)
                    .pushReplacementNamed('/home', arguments: targetAccountId);
                return; // Exit early after successful navigation
              }
            } else {
              // ignore: avoid_print
              print('[splash] OAuth completed but account is null or widget not mounted');
              // Clear processed link so we can retry
              _processedAppLink = null;
            }
          } else {
            // ignore: avoid_print
            print('[splash] OAuth state missing - this App Link is from a previous attempt');
            // Clear the App Link so it doesn't interfere with new sign-in attempts
            try {
              await methodChannel.invokeMethod('clearAppLink');
            } catch (_) {
              // Ignore if method not available
            }
            // Clear processed link
            _processedAppLink = null;
          }
        } else {
          // ignore: avoid_print
          print('[splash] No App Link found or no code parameter');
        }
      }
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[splash] error checking App Link: $e');
      // ignore: avoid_print
      print('[splash] stack trace: $stackTrace');
      // Clear processed link on error so we can retry
      _processedAppLink = null;
    }
  }

  Future<String?> _loadLastActiveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('lastActiveAccountId');
  }

  Future<void> _saveLastActiveAccount(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastActiveAccountId', accountId);
  }

  static const MethodChannel _channel = MethodChannel('com.seagreen.domail/bringToFront');

  Future<void> _bringAppToFront() async {
    // Works on desktop platforms using window_manager
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {
        // Ignore errors if window_manager is not initialized
      }
    }
    // On Android, use platform channel to bring app to front
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod('bringToFront');
      } catch (_) {
        // Ignore errors if method channel not set up
      }
    }
    // On iOS, navigation should bring app to front automatically
  }

  Future<void> _load() async {
    print('[splash] _load() started');
    final svc = GoogleAuthService();
    final accs = await svc.loadAccounts();
    print('[splash] loaded ${accs.length} accounts, _forceAdd=$_forceAdd, mounted=$mounted');
    setState(() {
      _accounts = accs;
    });
    if (_accounts.isNotEmpty && mounted && !_forceAdd) {
      print('[splash] auto-routing to home');
      // Get last active account from preferences
      final lastActiveAccountId = await _loadLastActiveAccount();
      
      // Find the account to use: last active if available, otherwise first
      GoogleAccount? accountToUse;
      if (lastActiveAccountId != null) {
        accountToUse = _accounts.firstWhere(
          (acc) => acc.id == lastActiveAccountId,
          orElse: () => _accounts.first,
        );
      } else {
        accountToUse = _accounts.first;
      }
      
      // Save the selected account as last active
      // accountToUse can never be null here since _accounts.isNotEmpty is checked above
      await _saveLastActiveAccount(accountToUse.id);
      
      // Auto-route to home using the selected account
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true)
          .pushNamedAndRemoveUntil('/home', (route) => false, arguments: accountToUse.id);
      return;
    }
    if (mounted && !_dialogShown) {
      print('[splash] showing dialog');
      _dialogShown = true;
      _showSplashWindow();
    }
  }

  void _showSplashWindow() async {
    print('[splash] _showSplashWindow() called');
    // Check for App Link right before showing dialog (in case app was resumed)
    if (Platform.isAndroid) {
      // ignore: avoid_print
      print('[splash] checking for App Link before showing dialog');
      await _checkAppLinkAndCompleteSignIn();
      if (!mounted) return; // If we navigated away, don't show dialog
    }
    
    // Capture navigators/messenger before awaiting dialog
    final dialogNavigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final result = await AppWindowDialog.show(
      context: context,
      title: _forceAdd ? 'Add Account' : 'Welcome to ${AppBrand.productName}',
      size: AppWindowSize.large,
      barrierDismissible: _forceAdd, // allow close only when explicitly adding
      bodyPadding: const EdgeInsets.all(32.0),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // App logo/icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.primary.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.email_outlined,
                    size: 60,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  AppBrand.productName,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 24),
                // Sign in button - moved directly below graphic, centered
                FilledButton.icon(
                  onPressed: _signingIn
                      ? null
                      : () async {
                    print('[splash] sign-in button pressed');
                    setState(() => _signingIn = true);
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    print('[splash] calling signIn()');
                    final svc = GoogleAuthService();
                    final acc = await svc.signIn();
                    print('[splash] signIn returned, mounted=$mounted, acc=${acc != null}');
                    if (!context.mounted) return;
                    if (acc != null) {
                      print('[splash] calling upsertAccount');
                      final stored = await svc.upsertAccount(acc);
                      print('[splash] upsertAccount done, mounted=$mounted');
                      if (!context.mounted) return;
                      // Save as last active account
                      print('[splash] saving last active account');
                      await _saveLastActiveAccount(stored.id);
                      print('[splash] saved, mounted=$mounted');
                      if (!context.mounted) return;
                      // Bring app to front after sign-in
                      await _bringAppToFront();
                      if (!context.mounted) return;

                      if (_forceAdd) {
                        // For add account flow, pop with account ID (this will pop AppWindowDialog)
                        dialogNavigator.pop(stored.id);
                      } else {
                        // For normal sign-in, navigate to home
                        _navigatedAway = true; // Mark as navigated to prevent pop attempts
                        rootNavigator.pushReplacementNamed('/home', arguments: stored.id);
                      }
                    } else {
                      // On Android, null might mean browser was launched and app will restart
                      // Don't show error - the app will restart and complete sign-in via App Link
                      if (Platform.isAndroid) {
                        print('[splash] Android sign-in: browser launched, waiting for app restart');
                        // Keep signing state - app will restart and complete sign-in
                      } else {
                        print('[splash] sign-in failed, showing snackbar');
                        scaffoldMessenger.showSnackBar(
                          const SnackBar(content: Text('Google sign-in not supported on this platform.')),
                        );
                        setState(() => _signingIn = false);
                      }
                    }
                  },
                  icon: const Icon(Icons.login),
                  label: Text(_signingIn ? 'Signing in…' : 'Sign in with Google'),
                ),
                const SizedBox(height: 8),
                Text(
                  'A better way to manage your email',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                Center(
                  child: Align(
                    alignment: Alignment.center,
                    child: Card(
                      elevation: 0,
                      color: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,       // shrink to fit content
                          crossAxisAlignment: CrossAxisAlignment.start, // left-align text within the block
                          children: [
                            _Benefit(icon: Icons.label_important_outline, text: 'Set and manage email actions'),
                            _Benefit(icon: Icons.swipe, text: 'Sort and store email, your way'),
                            _Benefit(icon: Icons.star_border_rounded, text: 'Never miss important emails'),
                          ],
                        ),
                      ),
                    ),
                  ),


                ),

              ],
            ),
          );
        },
      ),
    );
    print('[splash] AppWindowDialog.show() returned, result=$result');
    // If user dismissed the dialog without signing in, pop the route
    // But don't pop if we've already navigated away (e.g., from App Link completion)
    if (!context.mounted || _navigatedAway) {
      if (_navigatedAway) {
        // ignore: avoid_print
        print('[splash] already navigated away, skipping pop');
      }
      return;
    }
    if (_forceAdd) {
      print('[splash] forceAdd=true, popping SplashScreen route with result=$result');
      dialogNavigator.pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Read optional flag to prevent auto-route when adding accounts
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      _forceAdd = (args['forceAdd'] as bool?) ?? _forceAdd;
      print('[splash] build() called, _forceAdd=$_forceAdd from args');
    }
    // Provide a branded background with gradient
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.surface,
              theme.colorScheme.surfaceContainerHighest,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App logo
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.email_outlined,
                  size: 48,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppBrand.productName,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Benefit({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisSize: MainAxisSize.min, // shrink to fit content
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Text(
            text,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}



