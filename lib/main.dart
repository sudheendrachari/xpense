import 'dart:io';
import 'package:xpense/models/transaction.dart';
import 'package:xpense/screens/app_shell.dart';
import 'package:xpense/screens/setup_screen.dart';
import 'package:xpense/services/biometric_service.dart';
import 'package:xpense/services/database_service.dart';
import 'package:xpense/services/sms_service.dart';
import 'package:xpense/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check for cache clearing flag via environment variable
  // Usage: CLEAR_CACHE=true flutter run
  final shouldClearCache = Platform.environment['CLEAR_CACHE'] == 'true' ||
                          Platform.environment['FLUTTER_CLEAR_CACHE'] == 'true';
  
  if (shouldClearCache) {
    debugPrint('MAIN: Clearing cache as requested (CLEAR_CACHE=true)...');
    try {
      await DatabaseService().clearAll();
      debugPrint('MAIN: Cache cleared successfully');
    } catch (e) {
      debugPrint('MAIN: Error clearing cache: $e');
    }
  }
  
  // Set up MethodChannel for real-time SMS receiver
  _setupSmsReceiver();
  
  runApp(const MyApp());
}

// Global callback for real-time transaction updates (set by DashboardScreen)
Function(Transaction)? _onRealTimeTransactionSaved;

void setRealTimeTransactionCallback(Function(Transaction)? callback) {
  _onRealTimeTransactionSaved = callback;
}

void _setupSmsReceiver() {
  const MethodChannel channel = MethodChannel('xpense/sms_receiver');
  final SmsService smsService = SmsService();
  
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onSmsReceived') {
      try {
        final Map<dynamic, dynamic> smsData = call.arguments as Map<dynamic, dynamic>;
        final String sender = smsData['sender'] as String;
        final String body = smsData['body'] as String;
        final int timestamp = smsData['timestamp'] as int;
        final String id = smsData['id'] as String;
        
        debugPrint('MAIN: Received SMS from native: $sender');
        
        // Process SMS in background (don't block the receiver)
        smsService.processSingleSms(
          sender: sender,
          body: body,
          timestamp: timestamp,
          id: id,
          onTransactionSaved: (Transaction tx) {
            // Notify dashboard screen if callback is registered
            _onRealTimeTransactionSaved?.call(tx);
          },
        ).catchError((error) {
          debugPrint('MAIN: Error processing real-time SMS: $error');
          return false;
        });
      } catch (e) {
        debugPrint('MAIN: Error handling SMS receiver callback: $e');
      }
    }
  });
  
  debugPrint('MAIN: SMS receiver MethodChannel initialized');
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static _MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MyAppState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  bool _isDarkMode = false;
  bool? _isInitialSyncComplete;
  bool _isAuthenticated = false;
  bool _isBiometricEnabled = false;
  bool _isAuthenticating = false;
  AppLifecycleState? _lastState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreferences();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only auto-trigger if coming from BACKGROUND (paused), 
    // not just from a dialog closing (inactive).
    if (state == AppLifecycleState.resumed && 
        _lastState == AppLifecycleState.paused &&
        _isBiometricEnabled && 
        !_isAuthenticated && 
        !_isAuthenticating) {
      _authenticate();
    }
    _lastState = state;
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseService();
    final syncComplete = await db.isInitialSyncCompleted();
    final biometricEnabled = await BiometricService.isBiometricEnabled();
    
    if (mounted) {
      setState(() {
        _isDarkMode = prefs.getBool('dark_mode') ?? false;
        _isInitialSyncComplete = syncComplete;
        _isBiometricEnabled = biometricEnabled;
        // If biometric is disabled, consider user authenticated
        if (!biometricEnabled) {
          _isAuthenticated = true;
        }
      });

      if (biometricEnabled && !_isAuthenticated && !_isAuthenticating) {
        _authenticate();
      }
    }
  }

  void refreshPreferences() {
    _loadPreferences();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    if (mounted) {
      setState(() {
        _isAuthenticating = true;
      });
    }

    final authenticated = await BiometricService.authenticate();
    if (mounted) {
      setState(() {
        _isAuthenticated = authenticated;
        _isAuthenticating = false;
      });
    }
  }

  void _toggleDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
    if (mounted) {
      setState(() {
        _isDarkMode = value;
      });
    }
  }

  void _onSetupComplete() {
    if (mounted) {
      setState(() {
        _isInitialSyncComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xpense',
      debugShowCheckedModeBanner: false,
      theme: getAppTheme(isDark: false),
      darkTheme: getAppTheme(isDark: true),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    // Show loading while checking sync status
    if (_isInitialSyncComplete == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // Show lock screen if biometric is enabled and not yet authenticated
    if (_isBiometricEnabled && !_isAuthenticated) {
      return Scaffold(
        backgroundColor: AppColors.primary,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.white),
              const SizedBox(height: 24),
              Text(
                'Xpense is Locked',
                style: AppTextStyles.headlineMedium.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Unlock with Fingerprint'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show setup screen if initial sync not done
    if (_isInitialSyncComplete == false) {
      return SetupScreen(onSetupComplete: _onSetupComplete);
    }

    // Show main app with bottom navigation
    return AppShell(
      onThemeChanged: _toggleDarkMode,
      isDarkMode: _isDarkMode,
    );
  }
}
