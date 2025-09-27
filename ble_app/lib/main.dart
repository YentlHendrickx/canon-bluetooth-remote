import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'services/camera_ble_service.dart';
import 'services/watch_communication_service.dart';
import 'screens/device_selection_screen.dart';
import 'screens/camera_control_screen.dart';

final CameraBLEService _globalBleService = CameraBLEService.instance;
final WatchCommunicationService _watchService = WatchCommunicationService();
final Logger _logger = Logger();

// Global navigation key for handling navigation from services
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MainApp());
}

class AppLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        _logger.d('App paused - keeping connections alive');
        break;
      case AppLifecycleState.resumed:
        _logger.i('App resumed');
        _watchService.startListening();
        break;
      case AppLifecycleState.inactive:
        _logger.d('App inactive');
        break;
      case AppLifecycleState.hidden:
        _logger.d('App hidden');
        break;
      case AppLifecycleState.detached:
        _logger.i('App detached, performing cleanup');
        _globalBleService.handleAppTermination();
        _watchService.stopListening();
        break;
    }
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = AppLifecycleObserver();
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    // Start listening for watch commands
    _watchService.startListening();

    // Set up auto-connection callback
    _globalBleService.setAutoConnectionCallback(() {
      _logger.i('Auto-connection succeeded, navigating to camera control');
      // Navigate to camera control screen using global navigator key
      navigatorKey.currentState?.pushReplacementNamed('/camera_control');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Canon Camera Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Colors.white,
          iconColor: Colors.white70,
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1E1E1E),
          titleTextStyle: TextStyle(color: Colors.white),
          contentTextStyle: TextStyle(color: Colors.white70),
        ),
      ),
      home: const SplashScreen(),
      routes: {
        '/device_selection': (context) => const DeviceSelectionScreen(),
        '/camera_control': (context) => const CameraControlScreen(),
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.elasticOut),
      ),
    );

    _animationController.forward();
    _checkForSavedCamera();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkForSavedCamera() async {
    final bleService = CameraBLEService.instance;
    bleService.setConnectionOnStartup(); // let this run in the background
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) {
      return;
    }

    final savedAddress = await bleService.getSavedCameraAddress();
    _logger.i('Checking for saved camera: ${savedAddress ?? 'none'}');

    if (!mounted) {
      return;
    }

    if (savedAddress != null) {
      // Check if we can connect to the saved camera
      final isConnected = await bleService.isDeviceConnected();
      if (!mounted) {
        return;
      }

      if (isConnected) {
        _logger.i('Found connected camera, going to control screen');
        Navigator.of(context).pushReplacementNamed('/camera_control');
      } else {
        _logger.i(
          'Saved camera found but not connected, starting auto scan and going to device selection',
        );
        // Start passive monitoring for camera-initiated connections
        bleService.startPassiveConnectionMonitoring();
        Navigator.of(context).pushReplacementNamed('/device_selection');
      }
    } else {
      _logger.i('No saved camera, going to device selection');
      Navigator.of(context).pushReplacementNamed('/device_selection');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.white, Colors.grey.shade200],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(70),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 8,
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 0,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 70,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 40),

                    const Text(
                      'Camera Remote',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'Control your Canon camera wirelessly',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 16,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 60),

                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
