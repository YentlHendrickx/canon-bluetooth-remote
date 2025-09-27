import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'wear_platform_service.dart';

class PhoneCommunicationService {
  final Logger _logger = Logger();
  final WearPlatformService _wearPlatformService = WearPlatformService();

  // Wear OS Data Layer paths
  static const String _shutterCommandPath = '/shutter_command';

  /// Send shutter command to phone app
  Future<bool> sendShutterCommand() async {
    try {
      _logger.i('Sending shutter command to phone app...');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final command = {
        'action': 'trigger_shutter',
        'timestamp': timestamp,
        'source': 'watch',
        'id': timestamp.toString(),
      };

      final success = await _wearPlatformService.sendMessage(
        _shutterCommandPath,
        jsonEncode(command),
      );

      if (success) {
        _logger.i('Shutter command sent via Wear OS Data Layer');
        return true;
      }

      _logger.e('Failed to send shutter command via Wear OS Data Layer');
      return false;
    } catch (e) {
      _logger.e('Error sending shutter command: $e');
      return false;
    }
  }

  /// Check if phone app is connected
  Future<bool> isPhoneAppConnected() async {
    try {
      final connected = await _wearPlatformService.isConnected();
      if (connected) {
        _logger.d('Phone app connected via Wear OS Data Layer');
        return true;
      }

      _logger.w('Phone app not connected via Wear OS Data Layer');
      return false;
    } catch (e) {
      _logger.e('Error checking phone connection: $e');
      return false;
    }
  }

  /// Send status update to phone app
  Future<bool> sendStatusUpdate(String status) async {
    try {
      _logger.d('Sending status update: $status');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final statusData = {
        'action': 'status_update',
        'status': status,
        'timestamp': timestamp,
        'source': 'watch',
        'id': timestamp.toString(),
      };

      final success = await _wearPlatformService.sendMessage(
        _shutterCommandPath,
        jsonEncode(statusData),
      );

      if (!success) {
        _logger.e('Failed to send status update via Wear OS Data Layer');
      }

      return success;
    } catch (e) {
      _logger.e('Error sending status update: $e');
      return false;
    }
  }

  /// Listen for responses from phone app
  Stream<Map<String, dynamic>> listenForResponses() async* {
    final controller = StreamController<Map<String, dynamic>>.broadcast();

    _wearPlatformService.setMethodCallHandler((call) async {
      if (call.method == 'onShutterResponse') {
        final data = call.arguments['data'] as String?;
        if (data != null) {
          _logger.i('Received Wear OS shutter response: $data');
          try {
            final response = jsonDecode(data);
            controller.add(response);
          } catch (e) {
            _logger.e('Error parsing Wear OS response: $e');
          }
        }
      }
    });

    yield* controller.stream;
  }
}
