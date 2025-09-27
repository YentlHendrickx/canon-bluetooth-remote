import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import '../services/phone_communication_service.dart';

class WatchHomeScreen extends StatefulWidget {
  const WatchHomeScreen({super.key});

  @override
  State<WatchHomeScreen> createState() => _WatchHomeScreenState();
}

class _WatchHomeScreenState extends State<WatchHomeScreen>
    with TickerProviderStateMixin {
  final Logger _logger = Logger();
  final PhoneCommunicationService _phoneService = PhoneCommunicationService();

  bool _isShooting = false;
  bool _isConnected = false;
  late AnimationController _shutterAnimationController;
  late Animation<double> _shutterAnimation;
  StreamSubscription<Map<String, dynamic>>? _responseSubscription;
  Timer? _connectionCheckTimer;

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

    _checkPhoneConnection();
    _startListeningForResponses();
    _startConnectionMonitoring();
  }

  @override
  void dispose() {
    _shutterAnimationController.dispose();
    _responseSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkPhoneConnection() async {
    final connected = await _phoneService.isPhoneAppConnected();
    if (mounted) {
      setState(() {
        _isConnected = connected;
      });
    }
  }

  void _startListeningForResponses() {
    _responseSubscription = _phoneService.listenForResponses().listen(
      (response) {
        if (mounted) {
          _handlePhoneResponse(response);
        }
      },
      onError: (error) {
        _logger.e('Error listening for phone responses: $error');
      },
    );
  }

  void _startConnectionMonitoring() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _checkPhoneConnection();
    });
  }

  void _handlePhoneResponse(Map<String, dynamic> response) {
    final action = response['action'] as String?;
    final status = response['status'] as String?;
    final source = response['source'] as String?;

    if (source != 'phone') return;

    _logger.d('Received response from phone: $action - $status');

    switch (action) {
      case 'status_response':
        if (mounted) {
          setState(() {
            _isConnected = true;
          });
        }

        // Show status feedback and reset shooting state
        if (status == 'shutter_success') {
          _showSnackBar('Photo captured!', Colors.green);
          if (mounted) {
            setState(() {
              _isShooting = false;
            });
          }
        } else if (status == 'shutter_failed') {
          _showSnackBar('Capture failed', Colors.red);
          if (mounted) {
            setState(() {
              _isShooting = false;
            });
          }
        } else if (status == 'shutter_error') {
          _showSnackBar('Error occurred', Colors.orange);
          if (mounted) {
            setState(() {
              _isShooting = false;
            });
          }
        }
        break;
      case 'test_command':
        _logger.i('Received test command from phone');
        break;
    }
  }

  Future<void> _triggerShutter() async {
    if (_isShooting || !_isConnected) return;

    setState(() {
      _isShooting = true;
    });

    // Animate shutter button
    _shutterAnimationController.forward().then((_) {
      _shutterAnimationController.reverse();
    });

    try {
      _logger.i('Sending shutter command to phone...');
      final success = await _phoneService.sendShutterCommand();

      if (success) {
        _logger.i('Shutter command sent successfully');
        _showSnackBar('Sending...', Colors.blue);

        // Send status update to phone
        await _phoneService.sendStatusUpdate('shutter_requested');

        // Set a timeout to reset the UI state if no response comes back
        Timer(const Duration(seconds: 10), () {
          if (mounted && _isShooting) {
            _logger.w('Shutter timeout - no response from phone');
            setState(() {
              _isShooting = false;
            });
            _showSnackBar('Timeout - no response', Colors.orange);
          }
        });
      } else {
        _logger.e('Failed to send shutter command');
        _showSnackBar('Send failed', Colors.red);
        if (mounted) {
          setState(() {
            _isShooting = false;
          });
        }
      }
    } catch (e) {
      _logger.e('Error sending shutter command: $e');
      _showSnackBar('Error: $e', Colors.red);
      if (mounted) {
        setState(() {
          _isShooting = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Connection status
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? Colors.green : Colors.red,
                  boxShadow: [
                    BoxShadow(
                      color: (_isConnected ? Colors.green : Colors.red)
                          .withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Status text
              Text(
                _isConnected ? 'Ready' : 'No Phone',
                style: TextStyle(
                  color: _isConnected ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const SizedBox(height: 24),

              // Shutter button
              AnimatedBuilder(
                animation: _shutterAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _shutterAnimation.value,
                    child: GestureDetector(
                      onTap: _isConnected ? _triggerShutter : null,
                      child: Container(
                        width: 120,
                        height: 120,
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
                              color: (_isShooting ? Colors.red : Colors.white)
                                  .withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 10,
                              spreadRadius: 0,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isShooting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.camera_alt,
                                  size: 40,
                                  color: _isConnected
                                      ? Colors.black87
                                      : Colors.grey.shade400,
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // Instructions
              Text(
                _isShooting
                    ? 'Capturing...'
                    : _isConnected
                    ? 'Tap to capture'
                    : 'Connect phone app',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
