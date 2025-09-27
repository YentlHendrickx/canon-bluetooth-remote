import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class WearPlatformService {
  static const MethodChannel _channel = MethodChannel(
    'com.haze.canon_remote/wear_communication',
  );
  final Logger _logger = Logger();

  /// Check if phone app is connected
  Future<bool> isConnected() async {
    try {
      final bool connected = await _channel.invokeMethod('isConnected');
      _logger.d('Phone app connection status: $connected');
      return connected;
    } catch (e) {
      _logger.e('Error checking phone app connection: $e');
      return false;
    }
  }

  /// Send message to phone app
  Future<bool> sendMessage(String path, String message) async {
    try {
      await _channel.invokeMethod('sendMessage', {
        'path': path,
        'message': message,
      });
      _logger.d('Message sent to phone app: $path');
      return true;
    } catch (e) {
      _logger.e('Error sending message to phone app: $e');
      return false;
    }
  }

  /// Set method call handler for incoming messages
  void setMethodCallHandler(Future<dynamic> Function(MethodCall) handler) {
    _channel.setMethodCallHandler(handler);
  }
}
