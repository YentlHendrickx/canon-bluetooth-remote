import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class WearPlatformService {
  static const MethodChannel _channel = MethodChannel(
    'com.haze.canon_remote/wear_communication',
  );
  final Logger _logger = Logger();

  /// Check if Wear OS device is connected
  Future<bool> isConnected() async {
    try {
      final bool connected = await _channel.invokeMethod('isConnected');
      _logger.d('Wear OS connection status: $connected');
      return connected;
    } catch (e) {
      _logger.e('Error checking Wear OS connection: $e');
      return false;
    }
  }

  /// Send message to Wear OS device
  Future<bool> sendMessage(String path, String message) async {
    try {
      await _channel.invokeMethod('sendMessage', {
        'path': path,
        'message': message,
      });
      _logger.d('Message sent to Wear OS: $path');
      return true;
    } catch (e) {
      _logger.e('Error sending message to Wear OS: $e');
      return false;
    }
  }

  /// Get the device name from Android system
  Future<String> getDeviceName() async {
    try {
      final String deviceName = await _channel.invokeMethod('getDeviceName');
      _logger.d('Device name retrieved: $deviceName');
      return deviceName;
    } catch (e) {
      _logger.e('Error getting device name: $e');
      return 'Android Device';
    }
  }

  /// Set method call handler for incoming messages
  void setMethodCallHandler(Future<dynamic> Function(MethodCall) handler) {
    _channel.setMethodCallHandler(handler);
  }
}
