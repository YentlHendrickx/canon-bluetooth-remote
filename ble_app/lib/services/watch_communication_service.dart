import 'dart:async';
import 'dart:convert';
import 'package:logger/logger.dart';
import 'camera_ble_service.dart';
import 'wear_platform_service.dart';

class WatchCommunicationService {
  final Logger _logger = Logger();
  final CameraBLEService _cameraService = CameraBLEService.instance;
  final WearPlatformService _wearPlatformService = WearPlatformService();

  // Wear OS Data Layer paths
  static const String _shutterResponsePath = '/shutter_response';

  bool _isListening = false;

  /// Start listening for commands from the watch
  void startListening() {
    if (_isListening) return;

    _isListening = true;
    _logger.i('Starting watch command listener...');

    // Set up Wear OS message listener
    _wearPlatformService.setMethodCallHandler((call) async {
      if (call.method == 'onShutterCommand') {
        final data = call.arguments['data'] as String?;
        if (data != null) {
          _logger.i('Received Wear OS shutter command: $data');
          try {
            final command = jsonDecode(data);
            await _processCommand(command);
          } catch (e) {
            _logger.e('Error parsing Wear OS command: $e');
          }
        }
      }
    });
  }

  /// Stop listening for commands
  void stopListening() {
    _isListening = false;
    _logger.i('Stopped watch command listener');
  }

  /// Process a command from the watch
  Future<void> _processCommand(Map<String, dynamic> command) async {
    try {
      final action = command['action'] as String?;
      final source = command['source'] as String?;

      if (source != 'watch') return;

      _logger.i('Processing watch command: $action');

      switch (action) {
        case 'trigger_shutter':
          await _handleShutterCommand();
          break;
        case 'status_update':
          // Handle status update requests if needed
          _logger.i('Received status update request from watch');
          await _sendStatusToWatch('status_acknowledged');
          break;
        default:
          _logger.w('Unknown watch command: $action');
      }
    } catch (e) {
      _logger.e('Error processing watch command: $e');
    }
  }

  /// Handle shutter command from watch
  Future<void> _handleShutterCommand() async {
    try {
      _logger.i('Watch requested shutter trigger');

      // Trigger the camera shutter using the existing BLE service
      final success = await _cameraService.triggerShutter();

      if (success) {
        _logger.i('Shutter triggered successfully from watch');
        await _sendStatusToWatch('shutter_success');
      } else {
        _logger.e('Failed to trigger shutter from watch');
        await _sendStatusToWatch('shutter_failed');
      }
    } catch (e) {
      _logger.e('Error handling shutter command from watch: $e');
      await _sendStatusToWatch('shutter_error');
    }
  }

  /// Send status back to watch
  Future<void> _sendStatusToWatch(String status) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final statusData = {
        'action': 'status_response',
        'status': status,
        'timestamp': timestamp,
        'source': 'phone',
        'id': timestamp.toString(),
      };

      final success = await _wearPlatformService.sendMessage(
        _shutterResponsePath,
        jsonEncode(statusData),
      );

      if (success) {
        _logger.i('Status sent to watch via Wear OS Data Layer: $status');
      } else {
        _logger.e('Failed to send status to watch via Wear OS Data Layer');
      }
    } catch (e) {
      _logger.e('Error sending status to watch: $e');
    }
  }

  /// Check if watch is connected
  Future<bool> isWatchConnected() async {
    try {
      final connected = await _wearPlatformService.isConnected();
      if (connected) {
        _logger.d('Watch connected via Wear OS Data Layer');
        return true;
      }

      _logger.w('Watch not connected via Wear OS Data Layer');
      return false;
    } catch (e) {
      _logger.e('Error checking watch connection: $e');
      return false;
    }
  }

  /// Send test command to watch
  Future<void> sendTestCommand() async {
    try {
      _logger.i('Sending test command to watch via Wear OS Data Layer');
      await _wearPlatformService.sendMessage(
        _shutterResponsePath,
        jsonEncode({
          'action': 'test_command',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'source': 'phone',
        }),
      );
    } catch (e) {
      _logger.e('Error sending test command to watch: $e');
    }
  }
}
