import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:logger/logger.dart';
import '../services/camera_ble_service.dart';
import '../services/wear_platform_service.dart';

class DeviceSelectionScreen extends StatefulWidget {
  const DeviceSelectionScreen({super.key});

  @override
  State<DeviceSelectionScreen> createState() => _DeviceSelectionScreenState();
}

class _DeviceSelectionScreenState extends State<DeviceSelectionScreen> {
  final CameraBLEService _bleService = CameraBLEService.instance;
  final WearPlatformService _wearService = WearPlatformService();
  final Logger _logger = Logger();
  final List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  bool _isAutoScanning = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  String? _selectedDeviceId;
  bool _isConnecting = false;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _getDeviceName();
    _checkForAutoConnection();
    _startStatusUpdates();
  }

  void _startStatusUpdates() {
    // Update auto-scanning status every second
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateAutoScanStatus();
        // Navigation is now handled by the global callback in main.dart
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _checkForAutoConnection() async {
    // Check if we're already connected due to auto scanning
    await Future.delayed(const Duration(seconds: 1));
    if (mounted && _bleService.isConnected) {
      _logger.i(
        'Already connected to camera, navigation handled by global callback',
      );
    } else {
      // Check if auto scanning is active
      _updateAutoScanStatus();
    }
  }

  void _updateAutoScanStatus() {
    setState(() {
      _isAutoScanning = _bleService.isAutoScanning;
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
  }

  Future<void> _getDeviceName() async {
    try {
      final deviceName = await _wearService.getDeviceName();
      setState(() {
        _deviceName = deviceName;
      });
      _logger.i('Device name retrieved: $deviceName');
    } catch (e) {
      _logger.e('Failed to get device name: $e');
      setState(() {
        _deviceName = 'Android Device';
      });
    }
  }

  void _startScanning() {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _devices.clear();
    });

    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [],
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.platformName.isNotEmpty) {
          setState(() {
            if (!_devices.any(
              (device) => device.remoteId == result.device.remoteId,
            )) {
              _devices.add(result.device);
            }
          });
        }
      }
    });
  }

  void _stopScanning() {
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    setState(() {
      _isScanning = false;
    });
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _selectedDeviceId = device.remoteId.toString();
    });

    // First check if the device is already connected
    if (await device.connectionState.first ==
        BluetoothConnectionState.connected) {
      _logger.i('Device already connected, proceeding with pairing...');

      // Even if already connected, we need to pair with the camera
      // The camera expects a pairing handshake every time
      await _bleService.debugServices();

      // Save the phone name for future use
      if (_deviceName != null) {
        await _bleService.savePhoneName(_deviceName!);
      }

      await _bleService.saveCameraInfo(
        device.remoteId.toString(),
        device.platformName.isNotEmpty ? device.platformName : 'Unknown Camera',
      );

      // Perform pairing even for already connected devices
      bool paired = await _bleService.pairWithCamera(
        _deviceName ?? "Android Device",
      );

      if (paired) {
        _logger.i('Successfully paired with already connected device');
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/camera_control');
        }
      } else {
        _logger.w(
          'Failed to pair with already connected device, trying full connection flow...',
        );
        // If pairing fails, fall through to the full connection flow below
      }

      // If pairing succeeded, we're done
      if (paired) {
        return;
      }
    }

    try {
      await _bleService.forceDisconnect();
      await Future.delayed(const Duration(milliseconds: 1000));

      bool connected = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!connected && retryCount < maxRetries) {
        try {
          if (retryCount > 0) {
            _logger.i('Force disconnecting before retry ${retryCount + 1}');
            await _bleService.forceDisconnect();
            await Future.delayed(const Duration(seconds: 3));
          }

          connected = await _bleService.connectToCamera(
            device,
            deviceName: _deviceName ?? "Android Device",
          );
          if (!connected && retryCount < maxRetries - 1) {
            _logger.w(
              'Connection failed, retrying... (${retryCount + 1}/$maxRetries)',
            );
            await Future.delayed(const Duration(seconds: 3));
          }
        } catch (e) {
          _logger.e('Connection attempt ${retryCount + 1} failed: $e');
          if (retryCount < maxRetries - 1) {
            await _bleService.forceDisconnect();
            await Future.delayed(const Duration(seconds: 3));
          }
        }
        retryCount++;
      }

      if (connected) {
        // Connection and pairing already handled in connectToCamera()
        // Just navigate to control screen
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/camera_control');
        }
      } else {
        _showErrorDialog('Failed to connect to camera');
      }
    } catch (e) {
      _showErrorDialog('Connection error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _selectedDeviceId = null;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Error', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
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
            // Header
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Text(
                    'Camera Remote',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Connect to your Canon camera',
                    style: TextStyle(color: Colors.white60, fontSize: 16),
                  ),
                  if (_isAutoScanning) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.blue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Auto-scanning for saved camera...',
                          style: TextStyle(color: Colors.blue, fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Scan button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: _isScanning ? _stopScanning : _startScanning,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isScanning
                          ? [Colors.red, Colors.red.shade600]
                          : [Colors.white, Colors.grey.shade200],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (_isScanning ? Colors.red : Colors.white)
                            .withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 0,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isScanning) ...[
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Stop Scanning',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else ...[
                        const Icon(
                          Icons.bluetooth_searching,
                          color: Colors.black87,
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        const Text(
                          'Scan for Cameras',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Device list
            Expanded(
              child: _devices.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(60),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.bluetooth_disabled,
                              size: 60,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _isScanning
                                ? 'Scanning for cameras...'
                                : 'No cameras found',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isScanning
                                ? 'Make sure your camera is in pairing mode'
                                : 'Tap "Scan for Cameras" to start',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        final isSelected =
                            _selectedDeviceId == device.remoteId.toString();
                        final isConnecting = _isConnecting && isSelected;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.white.withValues(alpha: 0.1),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(25),
                              ),
                              child: const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            title: Text(
                              device.platformName.isNotEmpty
                                  ? device.platformName
                                  : 'Unknown Camera',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              device.remoteId.toString(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                            trailing: isConnecting
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
                                : const Icon(
                                    Icons.arrow_forward_ios,
                                    color: Colors.white70,
                                    size: 16,
                                  ),
                            onTap: isConnecting
                                ? null
                                : () => _connectToDevice(device),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
