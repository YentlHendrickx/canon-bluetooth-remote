import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../services/camera_ble_service.dart';
import '../services/watch_communication_service.dart';

class CameraControlScreen extends StatefulWidget {
  const CameraControlScreen({super.key});

  @override
  State<CameraControlScreen> createState() => _CameraControlScreenState();
}

class _CameraControlScreenState extends State<CameraControlScreen>
    with TickerProviderStateMixin {
  static final CameraBLEService _bleService = CameraBLEService.instance;
  static final WatchCommunicationService _watchService =
      WatchCommunicationService();
  final Logger _logger = Logger();
  String? _cameraName;
  String? _cameraAddress;
  bool _isShooting = false;
  bool _isWatchConnected = false;
  late AnimationController _shutterAnimationController;
  late Animation<double> _shutterAnimation;
  Timer? _connectionCheckTimer;
  Timer? _watchStatusTimer;

  @override
  void initState() {
    super.initState();
    _shutterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _shutterAnimation = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(
        parent: _shutterAnimationController,
        curve: Curves.easeInOut,
      ),
    );
    _loadCameraInfo();
    _startConnectionMonitoring();
    _startWatchStatusMonitoring();
  }

  @override
  void dispose() {
    _connectionCheckTimer?.cancel();
    _watchStatusTimer?.cancel();
    _shutterAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadCameraInfo() async {
    final name = await _bleService.getSavedCameraName();
    final address = await _bleService.getSavedCameraAddress();

    setState(() {
      _cameraName = name;
      _cameraAddress = address;
    });
  }

  void _startConnectionMonitoring() {
    // No persistent connection monitoring needed for session-per-shot workflow
    // Each shutter press will handle its own connection/disconnection
  }

  void _startWatchStatusMonitoring() {
    _watchStatusTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) async {
      if (mounted) {
        final isWatchConnected = await _watchService.isWatchConnected();
        if (mounted && _isWatchConnected != isWatchConnected) {
          setState(() {
            _isWatchConnected = isWatchConnected;
          });
        }
      }
    });
  }

  Future<void> _triggerShutter() async {
    if (_isShooting) return;

    if (_cameraAddress == null) {
      _showSnackBar(
        'No camera selected. Please select a camera first.',
        Colors.orange,
      );
      return;
    }

    setState(() {
      _isShooting = true;
    });

    // Animate shutter button
    _shutterAnimationController.forward().then((_) {
      _shutterAnimationController.reverse();
    });

    try {
      _logger.i('Starting shutter session...');
      bool success = await _bleService.triggerShutter();

      if (success) {
        _showSnackBar('Photo captured successfully!', Colors.green);
        _logger.i('Shutter session completed successfully');
      } else {
        _showSnackBar(
          'Failed to capture photo. Check camera connection.',
          Colors.red,
        );
        _logger.e('Shutter session failed');
      }
    } catch (e) {
      _logger.e('Shutter session error: $e');
      _showSnackBar('Error: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isShooting = false;
      });
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _disconnectCamera() async {
    await _bleService.disconnect();
    // await _bleService.clearSavedCameraInfo();

    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/device_selection');
    }
  }

  void _showDisconnectDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Disconnect Camera',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to disconnect from this camera?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _disconnectCamera();
            },
            child: const Text(
              'Disconnect',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with camera info and disconnect
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Camera info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _cameraName ?? 'Camera',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_cameraAddress != null)
                          Text(
                            _cameraAddress!,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Connection status and disconnect
                  Row(
                    children: [
                      // Watch connection indicator
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isWatchConnected ? Colors.blue : Colors.grey,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (_isWatchConnected
                                          ? Colors.blue
                                          : Colors.grey)
                                      .withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Session indicator
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isShooting ? Colors.red : Colors.green,
                          boxShadow: [
                            BoxShadow(
                              color: (_isShooting ? Colors.red : Colors.green)
                                  .withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Disconnect button
                      GestureDetector(
                        onTap: _showDisconnectDialog,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: const Icon(
                            Icons.bluetooth_disabled,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main shutter area
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shutter button
                    AnimatedBuilder(
                      animation: _shutterAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _shutterAnimation.value,
                          child: GestureDetector(
                            onTap: _triggerShutter,
                            child: Container(
                              width: 240,
                              height: 240,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    _isShooting ? Colors.red : Colors.white,
                                    _isShooting
                                        ? Colors.red.shade600
                                        : Colors.grey.shade300,
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_isShooting
                                                ? Colors.red
                                                : Colors.white)
                                            .withValues(alpha: 0.4),
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
                              child: Center(
                                child: _isShooting
                                    ? const SizedBox(
                                        width: 50,
                                        height: 50,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 4,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : const Icon(
                                        Icons.camera_alt,
                                        size: 80,
                                        color: Colors.black87,
                                      ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 40),

                    // Status text
                    Text(
                      _isShooting ? 'Capturing...' : 'Tap to capture',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Session status text
                    Text(
                      _isShooting ? 'Capturing...' : 'Ready to capture',
                      style: TextStyle(
                        color: _isShooting ? Colors.red : Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom padding
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
