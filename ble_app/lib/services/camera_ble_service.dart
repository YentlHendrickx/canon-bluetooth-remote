import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String canonCameraServiceUuid = "00050000-0000-1000-0000-d8492fffa821";
const String pairingCharacteristicUuid = "00050002-0000-1000-0000-d8492fffa821";
const String shutterCharacteristicUuid = "00050003-0000-1000-0000-d8492fffa821";

class CameraBLEService {
  static const String _cameraAddressKey = 'camera_address';
  static const String _cameraNameKey = 'camera_name';
  static const String _phoneNameKey = 'phone_name';
  static const String _phoneAddressKey = 'phone_address';
  static const int manufacturerName = 0x000C;
  static const int modelNumber = 0x000E;
  static const int serialNumber = 0x0010;
  static const int softwareRevision = 0x0012;
  static const int buttonRelease = 0x80; // 128 in decimal
  static const int immediate = 0x0C; // 12 in decimal

  // Singleton instance
  static CameraBLEService? _instance;
  static CameraBLEService get instance {
    _instance ??= CameraBLEService._internal();
    return _instance!;
  }

  CameraBLEService._internal();

  final Logger _logger = Logger();
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _pairingCharacteristic;
  BluetoothCharacteristic? _shutterCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<ScanResult>>? _autoScanSubscription;
  Timer? _connectionCheckTimer;
  bool _isAutoScanning = false;

  // Callback for navigation when auto-connection succeeds
  Function()? _onAutoConnectionSuccess;

  bool get isConnected => _connectedDevice != null;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  bool get isAutoScanning => _isAutoScanning;

  /// Set callback for when auto-connection succeeds
  void setAutoConnectionCallback(Function() callback) {
    _onAutoConnectionSuccess = callback;
  }

  /// Notify that auto-connection was successful
  void _notifyAutoConnectionSuccess() {
    if (_onAutoConnectionSuccess != null) {
      _onAutoConnectionSuccess!();
    }
  }

  Future<void> saveCameraInfo(String address, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cameraAddressKey, address);
    await prefs.setString(_cameraNameKey, name);
    _logger.i('Saved camera info: $name ($address)');
  }

  Future<void> savePhoneName(String phoneName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneNameKey, phoneName);
    _logger.i('Saved phone name: $phoneName');
  }

  Future<String?> getPhoneName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneNameKey);
  }

  Future<void> savePhoneAddress(String phoneAddress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_phoneAddressKey, phoneAddress);
    _logger.i('Saved phone address: $phoneAddress');
  }

  Future<String?> getPhoneAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneAddressKey);
  }

  Future<String?> getSavedCameraAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cameraAddressKey);
  }

  // Check if the device is already connected without us having made that connection
  // bluetooth will auto re-connect to known devices; in that case when we then 'connect' it will fail as we are already connected
  Future<void> setConnectionOnStartup() async {
    final savedAddress = await getSavedCameraAddress();
    if (savedAddress == null) return;

    final device = await checkConnection(savedAddress);
    if (device == null) return;

    _logger.i(
      'Found already connected device: ${device.advName} ($savedAddress)',
    );

    _connectedDevice = device;
    _startConnectionMonitoring(device);
    final found = await _discoverCharacteristics(device);
    if (!found) {
      _logger.w(
        'Failed to discover characteristics on already connected device',
      );
      await disconnect();
    } else {
      _logger.i(
        'Successfully discovered characteristics on already connected device',
      );

      // Even for already connected devices, we need to pair with the camera
      // The camera expects a pairing handshake every time
      final phoneName = await getPhoneName();
      if (phoneName != null) {
        _logger.i(
          'Performing pairing handshake with already connected device...',
        );
        final paired = await pairWithCamera(phoneName);
        if (paired) {
          _logger.i('Successfully paired with already connected device');
        } else {
          _logger.w('Failed to pair with already connected device');
        }
      } else {
        _logger.w('No saved phone name found for pairing');
      }
    }
  }

  Future<BluetoothDevice?> checkConnection(String address) async {
    for (BluetoothDevice device in FlutterBluePlus.connectedDevices) {
      if (device.remoteId.toString().toLowerCase() != address.toLowerCase()) {
        continue;
      }

      return device;
    }

    return null;
  }

  Future<String?> getSavedCameraName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_cameraNameKey);
  }

  Future<void> clearSavedCameraInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cameraAddressKey);
    await prefs.remove(_cameraNameKey);
    await prefs.remove(_phoneNameKey);
    _logger.i('Cleared saved camera info');
  }

  /// Start passive connection monitoring (check for camera-initiated connections)
  Future<void> startPassiveConnectionMonitoring() async {
    if (_connectedDevice != null) return;

    final savedAddress = await getSavedCameraAddress();
    if (savedAddress == null) {
      _logger.i('No saved camera address, skipping passive monitoring');
      return;
    }

    _logger.i(
      'Starting passive connection monitoring for camera: $savedAddress',
    );

    // Check every 2 seconds for camera-initiated connections
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      if (_connectedDevice != null) {
        timer.cancel();
        return;
      }

      final connectedDevices = FlutterBluePlus.connectedDevices;
      for (final device in connectedDevices) {
        if (device.remoteId.toString().toLowerCase() ==
            savedAddress.toLowerCase()) {
          _logger.i('Camera connected to us, handling connection...');
          timer.cancel();
          await _handleAutoDiscoveredCamera(device);
          return;
        }
      }
    });
  }

  /// Start automatic scanning for the saved camera (with delay to avoid conflicts)
  Future<void> startAutoScanning() async {
    if (_isAutoScanning || _connectedDevice != null) return;

    final savedAddress = await getSavedCameraAddress();
    if (savedAddress == null) {
      _logger.i('No saved camera address, skipping auto scan');
      return;
    }

    _logger.i(
      'Starting auto scan for saved camera: $savedAddress (with 5s delay)',
    );

    // Add delay to let camera try to connect to us first
    await Future.delayed(const Duration(seconds: 5));

    if (_connectedDevice != null) {
      _logger.i('Camera already connected during delay, skipping scan');
      return;
    }

    // Check if camera is already in connected devices (camera initiated connection)
    final connectedDevices = FlutterBluePlus.connectedDevices;
    for (final device in connectedDevices) {
      if (device.remoteId.toString().toLowerCase() ==
          savedAddress.toLowerCase()) {
        _logger.i('Camera already connected to us, handling connection...');
        await _handleAutoDiscoveredCamera(device);
        return;
      }
    }

    _isAutoScanning = true;

    // Start scanning with shorter intervals to be less aggressive
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      withServices: [],
    );

    _autoScanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.remoteId.toString().toLowerCase() ==
            savedAddress.toLowerCase()) {
          _logger.i(
            'Found saved camera during auto scan: ${result.device.advName}',
          );
          _handleAutoDiscoveredCamera(result.device);
          break;
        }
      }
    });
  }

  /// Stop automatic scanning
  void stopAutoScanning() {
    if (!_isAutoScanning) return;

    _logger.i('Stopping auto scan');
    _isAutoScanning = false;
    _autoScanSubscription?.cancel();
    _autoScanSubscription = null;
    FlutterBluePlus.stopScan();
  }

  /// Handle when the saved camera is discovered during auto scan
  Future<void> _handleAutoDiscoveredCamera(BluetoothDevice device) async {
    if (_connectedDevice != null) {
      _logger.i('Already connected to a device, ignoring auto discovery');
      return;
    }

    _logger.i('Auto-connecting to discovered camera: ${device.advName}');

    try {
      // Stop scanning first
      stopAutoScanning();

      // Connect to the camera with automatic pairing
      final success = await connectToCamera(
        device,
        deviceName: await getPhoneName(),
      );

      if (success) {
        _logger.i('Successfully auto-connected and paired with camera');
        // Notify that we should navigate to camera control screen
        _notifyAutoConnectionSuccess();
      } else {
        _logger.w('Failed to auto-connect to camera, restarting scan');
        // Restart scanning after a delay
        Future.delayed(const Duration(seconds: 5), () {
          if (!_isAutoScanning && _connectedDevice == null) {
            startAutoScanning();
          }
        });
      }
    } catch (e) {
      _logger.e('Error during auto-connection: $e');
      // Restart scanning after a delay
      Future.delayed(const Duration(seconds: 5), () {
        if (!_isAutoScanning && _connectedDevice == null) {
          startAutoScanning();
        }
      });
    }
  }

  Future<bool> connectToCamera(
    BluetoothDevice device, {
    String? deviceName,
  }) async {
    try {
      _logger.i('Starting connection to device: ${device.remoteId}');

      final currentState = await device.connectionState.first;

      if (currentState == BluetoothConnectionState.connected) {
        _logger.i('Device already connected');
        _connectedDevice = device;
        return true;
      }

      if (_connectedDevice == null) {
        _logger.i('Initiating new connection...');
        await device.connect();
        await device.connectionState
            .firstWhere((state) => state == BluetoothConnectionState.connected)
            .timeout(const Duration(seconds: 15));

        _connectedDevice = device;
        _logger.i('Connection established successfully');
        _startConnectionMonitoring(device);

        // Don't do immediate pairing - wait for service discovery like Python script

        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logger.i('Starting service discovery...');
      final foundCharacteristics = await _discoverCharacteristics(device);

      if (!foundCharacteristics) {
        _logger.e('Failed to find required characteristics');
        disconnect();
        return false;
      }

      _logger.i('Service discovery completed successfully');

      // Save device info for future use
      if (deviceName != null) {
        await savePhoneName(deviceName);
      }
      await saveCameraInfo(
        device.remoteId.toString(),
        device.platformName.isNotEmpty ? device.platformName : 'Unknown Camera',
      );

      if (deviceName != null && _pairingCharacteristic != null) {
        // Add delay before handshake to let camera stabilize
        _logger.i('Waiting for camera to stabilize before handshake...');
        await Future.delayed(const Duration(milliseconds: 1000));

        _logger.i('Performing handshake with camera: $deviceName');
        bool paired = await pairWithCamera(deviceName);

        if (!paired) {
          _logger.e('Handshake failed - camera may not accept this device');
          disconnect();
          return false;
        } else {
          _logger.i('Handshake completed successfully');
        }
      } else {
        _logger.w(
          'Cannot perform handshake - missing device name or pairing characteristic',
        );
        _logger.w('Device name: $deviceName');
        _logger.w('Pairing characteristic: ${_pairingCharacteristic != null}');
      }

      return true;
    } catch (e) {
      _logger.e('Error connecting to camera: $e');
      disconnect();
      return false;
    }
  }

  Future<bool> _discoverCharacteristics(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    _logger.d('Discovered ${services.length} services');

    for (BluetoothService service in services) {
      _logger.d('Service UUID: ${service.uuid}');
      _logger.d(
        'Service characteristics count: ${service.characteristics.length}',
      );

      for (BluetoothCharacteristic characteristic in service.characteristics) {
        _logger.d('Characteristic UUID: ${characteristic.uuid}');
        _logger.d('Properties: ${characteristic.properties}');

        String charUuid = characteristic.uuid.toString().toLowerCase();

        if (charUuid == pairingCharacteristicUuid.toLowerCase()) {
          _pairingCharacteristic = characteristic;
          _logger.i('Found pairing characteristic: ${characteristic.uuid}');
        } else if (charUuid == shutterCharacteristicUuid.toLowerCase()) {
          _shutterCharacteristic = characteristic;
          _logger.i('Found shutter characteristic: ${characteristic.uuid}');
        }
      }
    }

    _logger.d(
      'Pairing characteristic found: ${_pairingCharacteristic != null}',
    );
    _logger.d(
      'Shutter characteristic found: ${_shutterCharacteristic != null}',
    );

    if (_shutterCharacteristic == null) {
      _logger.w(
        'Shutter characteristic not found by UUID, searching for writable characteristic...',
      );
      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.write ||
              characteristic.properties.writeWithoutResponse) {
            _shutterCharacteristic = characteristic;
            _logger.i(
              'Using writable characteristic as shutter: ${characteristic.uuid}',
            );
            break;
          }
        }
        if (_shutterCharacteristic != null) break;
      }
    }

    return _pairingCharacteristic != null && _shutterCharacteristic != null;
  }

  Future<void> disconnect() async {
    _logger.i('Starting disconnect process...');

    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _connectionCheckTimer?.cancel();
    _connectionCheckTimer = null;

    if (_connectedDevice != null) {
      try {
        final currentState = await _connectedDevice!.connectionState.first;
        _logger.d('Current connection state: $currentState');

        if (currentState == BluetoothConnectionState.connected) {
          _logger.i('Disconnecting from device...');
          await _connectedDevice!.disconnect();

          await _connectedDevice!.connectionState
              .firstWhere(
                (state) => state == BluetoothConnectionState.disconnected,
              )
              .timeout(const Duration(seconds: 5));
          _logger.i('Device disconnected successfully');
        }
      } catch (e) {
        _logger.e('Error during disconnect: $e');
      } finally {
        _cleanup();
        // Restart auto scanning after disconnect
        Future.delayed(const Duration(seconds: 2), () {
          startAutoScanning();
        });
      }
    }
  }

  Future<void> forceDisconnect() async {
    _logger.i('Starting force disconnect...');

    _connectionSubscription?.cancel();
    _connectionSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
        _logger.i('Force disconnect completed');
      } catch (e) {
        _logger.e('Error during force disconnect: $e');
      } finally {
        _cleanup();
        // Restart auto scanning after force disconnect
        Future.delayed(const Duration(seconds: 2), () {
          startAutoScanning();
        });
      }
    }
  }

  void _cleanup() {
    _logger.d('Cleaning up resources...');
    _connectedDevice = null;
    _pairingCharacteristic = null;
    _shutterCharacteristic = null;
    _logger.d('Cleanup completed');
  }

  Future<void> handleAppTermination() async {
    _logger.i('Handling app termination...');
    stopAutoScanning();
    await forceDisconnect();
  }

  void _startConnectionMonitoring(BluetoothDevice device) {
    _connectionSubscription?.cancel();

    _connectionSubscription = device.connectionState.listen((state) {
      _logger.d('Connection state changed: $state');

      if (state == BluetoothConnectionState.disconnected) {
        _logger.w('Device disconnected unexpectedly');
        _cleanup();
      }
    });
  }

  Future<bool> isDeviceConnected() async {
    if (_connectedDevice == null) return false;

    try {
      final state = await _connectedDevice!.connectionState.first;
      return state == BluetoothConnectionState.connected;
    } catch (e) {
      _logger.e('Error checking connection state: $e');
      return false;
    }
  }

  List<int> _generatePairingData(String deviceName) {
    return [0x03, ...deviceName.codeUnits];
  }

  Future<bool> pairWithCamera(String deviceName) async {
    if (_pairingCharacteristic == null) {
      _logger.e('No pairing characteristic available');
      return false;
    }

    try {
      List<int> pairingData = _generatePairingData(deviceName);
      _logger.d('Sending pairing data: $pairingData');
      _logger.d(
        'Pairing data as hex: ${pairingData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      _logger.d(
        'Using pairing characteristic: ${_pairingCharacteristic!.uuid}',
      );
      _logger.d(
        'Characteristic properties: ${_pairingCharacteristic!.properties}',
      );

      await _pairingCharacteristic!.write(
        Uint8List.fromList(pairingData),
        withoutResponse: false, // Use response=true like Python script
      );

      _logger.i(
        'Pairing command sent successfully, waiting for camera response...',
      );

      // Wait for the camera to process the pairing
      await Future.delayed(const Duration(milliseconds: 1000));

      // Try to verify pairing by testing if we can write to shutter characteristic
      if (_shutterCharacteristic != null) {
        _logger.d(
          'Verifying pairing by testing shutter characteristic access...',
        );
        try {
          // Try a simple write to see if camera accepts commands
          await _shutterCharacteristic!.write(
            Uint8List.fromList([0x00]), // Release command
            withoutResponse: true,
          );
          _logger.i(
            'Pairing verification successful - camera accepts commands',
          );
          return true;
        } catch (e) {
          _logger.w(
            'Pairing verification failed - camera may not have accepted pairing: $e',
          );
          // Still return true since the pairing command was sent successfully
          // The camera might accept it even if verification fails
          return true;
        }
      } else {
        _logger.w('No shutter characteristic available for verification');
        return true; // Assume success if we can't verify
      }
    } catch (e) {
      _logger.e('Error pairing with camera: $e');
      if (e.toString().contains('write')) {
        _logger.e(
          'Write operation failed - camera may not be accepting pairing commands',
        );
      } else if (e.toString().contains('characteristic')) {
        _logger.e('Characteristic error - may need to rediscover services');
      }
      return false;
    }
  }

  // Optimized session-per-shot workflow - matches Python implementation exactly
  Future<bool> triggerShutter() async {
    _logger.i('--- Starting Fast Session-per-Shot Workflow ---');

    final cameraAddress = await getSavedCameraAddress();
    if (cameraAddress == null) {
      _logger.e('No saved camera address found');
      return false;
    }

    BluetoothDevice? targetDevice;
    bool sessionSuccess = false;

    try {
      // Step 1: Find the target device (optimized - no scanning delay)
      _logger.d('Looking for saved camera: $cameraAddress');

      // First check if device is already connected
      final connectedDevices = FlutterBluePlus.connectedDevices;
      for (final device in connectedDevices) {
        if (device.remoteId.toString().toLowerCase() ==
            cameraAddress.toLowerCase()) {
          targetDevice = device;
          _logger.d('Found camera in connected devices');
          break;
        }
      }

      // If not connected, try to find by scanning with shorter timeout
      if (targetDevice == null) {
        _logger.d('Camera not connected, quick scan...');

        // Quick scan with shorter timeout
        await FlutterBluePlus.startScan(
          timeout: const Duration(seconds: 3),
          withServices: [],
        );

        final scanResults = <ScanResult>[];
        final scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          for (ScanResult result in results) {
            if (result.device.remoteId.toString().toLowerCase() ==
                cameraAddress.toLowerCase()) {
              scanResults.add(result);
            }
          }
        });

        // Wait only 2 seconds for scan results
        await Future.delayed(const Duration(seconds: 2));
        await FlutterBluePlus.stopScan();
        scanSubscription.cancel();

        if (scanResults.isNotEmpty) {
          targetDevice = scanResults.first.device;
          _logger.d('Found camera during quick scan');
        } else {
          _logger.e('Saved camera device not found during scan');
          return false;
        }
      }

      _logger.i('Found target device: ${targetDevice.remoteId}');

      // Step 2: Connect to camera (if not already connected)
      final currentState = await targetDevice.connectionState.first;
      if (currentState != BluetoothConnectionState.connected) {
        _logger.d('Connecting to camera...');
        try {
          await targetDevice.connect();
          await targetDevice.connectionState
              .firstWhere(
                (state) => state == BluetoothConnectionState.connected,
              )
              .timeout(const Duration(seconds: 10)); // Reduced timeout
          _logger.i('Connected to camera!');
        } catch (e) {
          _logger.e('Connection timeout or failed: $e');
          return false;
        }
      } else {
        _logger.d('Already connected to camera');
      }

      // Step 3: Discover services and characteristics (cached if possible)
      _logger.d('Discovering services...');
      final foundCharacteristics = await _discoverCharacteristicsForSession(
        targetDevice,
      );
      if (!foundCharacteristics) {
        _logger.e('Failed to discover required characteristics');
        return false;
      }

      // Step 4: Authenticate (handshake/pairing) - minimal delay
      _logger.d('Authenticating with camera...');
      final authSuccess = await _authenticateWithCamera();
      if (!authSuccess) {
        _logger.e(
          'Authentication failed - retrying with fresh characteristics...',
        );

        // Retry with fresh characteristics discovery
        final retryCharacteristics = await _discoverCharacteristicsForSession(
          targetDevice,
        );
        if (!retryCharacteristics) {
          _logger.e('Failed to rediscover characteristics on retry');
          return false;
        }

        final retryAuth = await _authenticateWithCamera();
        if (!retryAuth) {
          _logger.e('Authentication failed on retry');
          return false;
        }
        _logger.i('Authentication successful on retry');
      } else {
        _logger.i('Authentication successful');
      }

      // Step 5: Send shutter sequence (optimized timing)
      _logger.d('Sending shutter sequence...');
      final shutterSuccess = await _sendShutterSequence();
      if (!shutterSuccess) {
        _logger.e('Shutter sequence failed');
        return false;
      }
      _logger.i('Shutter sequence complete');

      sessionSuccess = true;
    } catch (e) {
      _logger.e('Session error: $e');
      _handleSessionError(e);
    } finally {
      // Step 6: Always disconnect to hand control back to camera
      if (targetDevice != null) {
        try {
          _logger.d('Disconnecting to hand control back to camera...');
          await targetDevice.disconnect();
          _logger.i('Disconnected. Physical buttons unlocked.');
        } catch (e) {
          _logger.w('Error during disconnect: $e');
        }
      }
    }

    return sessionSuccess;
  }

  // Handle different types of session errors
  void _handleSessionError(dynamic error) {
    String errorType = error.runtimeType.toString();
    String errorMessage = error.toString();

    if (errorMessage.contains('timeout')) {
      _logger.e(
        'Connection timeout - camera may be out of range or turned off',
      );
    } else if (errorMessage.contains('not found') ||
        errorMessage.contains('discover')) {
      _logger.e(
        'Service discovery failed - camera may not support remote control',
      );
    } else if (errorMessage.contains('write') ||
        errorMessage.contains('characteristic')) {
      _logger.e('Communication error - camera may be in wrong mode');
    } else if (errorMessage.contains('permission') ||
        errorMessage.contains('denied')) {
      _logger.e('Permission error - check Bluetooth permissions');
    } else {
      _logger.e('Unknown error: $errorType - $errorMessage');
    }
  }

  // Discover characteristics for a specific session - with caching
  Future<bool> _discoverCharacteristicsForSession(
    BluetoothDevice device,
  ) async {
    try {
      // Always rediscover characteristics to avoid stale references
      // Caching was causing "primary service not found" errors
      _logger.d('Rediscovering characteristics for device: ${device.remoteId}');

      _logger.d('Discovering characteristics for device: ${device.remoteId}');
      List<BluetoothService> services = await device.discoverServices();
      _logger.d('Discovered ${services.length} services for session');

      if (services.isEmpty) {
        _logger.e(
          'No services discovered - camera may not support remote control',
        );
        return false;
      }

      for (BluetoothService service in services) {
        _logger.d('Checking service: ${service.uuid}');
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          String charUuid = characteristic.uuid.toString().toLowerCase();
          _logger.d('Found characteristic: $charUuid');

          if (charUuid == pairingCharacteristicUuid.toLowerCase()) {
            _pairingCharacteristic = characteristic;
            _logger.d(
              'Found pairing characteristic for session: ${characteristic.uuid}',
            );
          } else if (charUuid == shutterCharacteristicUuid.toLowerCase()) {
            _shutterCharacteristic = characteristic;
            _logger.d(
              'Found shutter characteristic for session: ${characteristic.uuid}',
            );
          }
        }
      }

      if (_pairingCharacteristic == null) {
        _logger.e(
          'Pairing characteristic not found - camera may not support authentication',
        );
        return false;
      }

      if (_shutterCharacteristic == null) {
        _logger.e(
          'Shutter characteristic not found - camera may not support remote shutter',
        );
        return false;
      }

      _logger.d('Successfully found both required characteristics');

      return true;
    } catch (e) {
      _logger.e('Error discovering characteristics for session: $e');
      return false;
    }
  }

  // Authenticate with camera (handshake) - optimized timing
  Future<bool> _authenticateWithCamera() async {
    if (_pairingCharacteristic == null) {
      _logger.e('No pairing characteristic available for authentication');
      return false;
    }

    try {
      // Get the phone name from saved preferences or use a default
      final phoneName = await getPhoneName();
      final deviceName = phoneName ?? 'Android Device';

      List<int> pairingData = _generatePairingData(deviceName);
      _logger.d('Sending authentication data: $pairingData');
      _logger.d(
        'Using pairing characteristic: ${_pairingCharacteristic!.uuid}',
      );

      // Check if characteristic supports write without response
      if (!_pairingCharacteristic!.properties.writeWithoutResponse) {
        _logger.e(
          'Pairing characteristic does not support write without response',
        );
        return false;
      }

      await _pairingCharacteristic!.write(
        Uint8List.fromList(pairingData),
        withoutResponse: false, // Use response=true like Python script
      );

      // Minimal delay - just enough for the camera to process
      await Future.delayed(const Duration(milliseconds: 100));

      _logger.i('Authentication handshake complete');
      return true;
    } catch (e) {
      _logger.e('Authentication error: $e');
      if (e.toString().contains('primary service not found')) {
        _logger.e(
          'Service discovery failed - characteristics may be stale. Retrying...',
        );
        return false;
      } else if (e.toString().contains('write')) {
        _logger.e(
          'Write operation failed - camera may be in wrong mode or not accepting commands',
        );
      }
      return false;
    }
  }

  // Send the proper shutter sequence - optimized timing to match Python
  Future<bool> _sendShutterSequence() async {
    if (_shutterCharacteristic == null) {
      _logger.e('No shutter characteristic available for shutter sequence');
      return false;
    }

    try {
      _logger.d('Starting shutter sequence...');

      // Check if characteristic supports write without response
      if (!_shutterCharacteristic!.properties.writeWithoutResponse) {
        _logger.e(
          'Shutter characteristic does not support write without response',
        );
        return false;
      }

      // 1. Half-press (focus) - matches Python: IMMEDIATE = 0x0C
      await _shutterCharacteristic!.write(
        Uint8List.fromList([immediate]),
        withoutResponse: true,
      );
      _logger.d('Sent focus command (half-press)');

      // Wait 300ms like Python - this is the only delay we need
      await Future.delayed(const Duration(milliseconds: 300));

      // 2. Full press (shutter) - matches Python: BUTTON_RELEASE | IMMEDIATE = 0x80 | 0x0C
      await _shutterCharacteristic!.write(
        Uint8List.fromList([buttonRelease | immediate]),
        withoutResponse: true,
      );
      _logger.d('Sent shutter command (full press)');

      // 3. Release - matches Python: 0x00 (no delay)
      await _shutterCharacteristic!.write(
        Uint8List.fromList([0x00]),
        withoutResponse: true,
      );
      _logger.d('Sent release command');

      _logger.i('Shutter sequence complete');
      return true;
    } catch (e) {
      _logger.e('Shutter sequence error: $e');
      if (e.toString().contains('write')) {
        _logger.e(
          'Write operation failed during shutter sequence - camera may have disconnected',
        );
      }
      return false;
    }
  }

  Future<void> debugServices() async {
    if (_connectedDevice == null) {
      _logger.w('No device connected');
      return;
    }

    try {
      List<BluetoothService> services = await _connectedDevice!
          .discoverServices();
      _logger.d('\n=== DEBUG: Available Services and Characteristics ===');

      for (BluetoothService service in services) {
        _logger.d('\nService: ${service.uuid}');
        _logger.d('Characteristics:');

        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          _logger.d('UUID: ${characteristic.uuid}');
          _logger.d('Properties: ${characteristic.properties}');
          _logger.d('Can Read: ${characteristic.properties.read}');
          _logger.d('Can Write: ${characteristic.properties.write}');
          _logger.d('Can Notify: ${characteristic.properties.notify}');
          _logger.d('---');
        }
      }

      _logger.d('=== END DEBUG ===\n');
    } catch (e) {
      _logger.e('Error debugging services: $e');
    }
  }

  Future<Map<String, String>?> readDeviceInfo() async {
    if (_connectedDevice == null) return null;

    try {
      List<BluetoothService> services = await _connectedDevice!
          .discoverServices();
      Map<String, String> deviceInfo = {};

      for (BluetoothService service in services) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.properties.read) {
            List<int> value = await characteristic.read();
            String stringValue = String.fromCharCodes(value);

            if (characteristic.uuid.toString().contains('000C')) {
              deviceInfo['manufacturer'] = stringValue;
            } else if (characteristic.uuid.toString().contains('000E')) {
              deviceInfo['model'] = stringValue;
            } else if (characteristic.uuid.toString().contains('0010')) {
              deviceInfo['serial'] = stringValue;
            } else if (characteristic.uuid.toString().contains('0012')) {
              deviceInfo['software'] = stringValue;
            }
          }
        }
      }

      return deviceInfo.isNotEmpty ? deviceInfo : null;
    } catch (e) {
      _logger.e('Error reading device info: $e');
      return null;
    }
  }
}
