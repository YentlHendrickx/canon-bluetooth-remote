# Camera Remote Watch App

A Wear OS companion app for the Camera Remote phone app that allows you to trigger camera shutter from your smartwatch.

## Features

- **Simple Interface**: Large, easy-to-tap shutter button optimized for watch screens
- **Connection Status**: Visual indicator showing connection to phone app
- **Haptic Feedback**: Vibration feedback when shutter is triggered
- **Ambient Mode**: Works in both active and ambient watch modes
- **Session-based**: Each shutter press is a complete session (connect → authenticate → capture → disconnect)

## Setup

### Prerequisites

1. **Wear OS Watch**: Compatible with Wear OS 3.0+
2. **Phone App**: The main Camera Remote phone app must be installed and running
3. **Camera**: Canon camera with BLE support

### Installation

1. **Build the Watch App**:
   ```bash
   cd camera_watch_app
   flutter build apk --target-platform android-arm64
   ```

2. **Install on Watch**:
   - Connect your watch to your computer via ADB
   - Install the APK: `adb install build/app/outputs/flutter-apk/app-release.apk`

3. **Pair with Phone**:
   - Make sure the phone app is running
   - The watch app will automatically detect the phone app
   - Blue indicator shows when connected

## Usage

1. **Launch the Watch App**: Find "Camera Remote Watch" in your watch's app drawer
2. **Check Connection**: Look for the blue indicator dot (connected) or grey (disconnected)
3. **Trigger Shutter**: Tap the large white button to capture a photo
4. **Feedback**: Watch will vibrate and show status when photo is captured

## Communication Flow

```
Watch App → Phone App → Camera
    ↓           ↓         ↓
  Tap Button → BLE Service → Shutter
```

1. **Watch**: User taps shutter button
2. **Phone**: Receives command via communication service
3. **Camera**: Phone app triggers camera using existing BLE service
4. **Feedback**: Status is sent back to watch

## Technical Details

### Communication Method

Currently uses SharedPreferences for communication between watch and phone (simplified for development). In production, this should be replaced with:

- **Wearable Data Layer API**: For reliable communication
- **Message API**: For real-time commands
- **Data Sync**: For persistent data sharing

### Architecture

- **Watch App**: Simple UI with communication service
- **Phone App**: Enhanced with watch communication service
- **BLE Service**: Unchanged, handles camera communication

### File Structure

```
camera_watch_app/
├── lib/
│   ├── main.dart                    # App entry point
│   ├── screens/
│   │   └── watch_home_screen.dart   # Main watch interface
│   └── services/
│       └── phone_communication_service.dart  # Communication with phone
└── android/
    └── app/src/main/
        └── AndroidManifest.xml      # Wear OS configuration
```

## Development Notes

### Current Implementation

- Uses SharedPreferences for communication (simplified)
- Watch app polls for commands every second
- Phone app listens for watch commands
- Status updates sent back to watch

### Production Improvements Needed

1. **Replace SharedPreferences** with Wearable Data Layer API
2. **Add proper error handling** for communication failures
3. **Implement connection management** for watch disconnection
4. **Add settings** for watch-specific configurations
5. **Optimize battery usage** for watch app

### Testing

1. **Phone App**: Test camera connection and shutter functionality
2. **Watch App**: Test button responsiveness and feedback
3. **Communication**: Test command flow from watch to phone
4. **Integration**: Test complete flow from watch to camera

## Troubleshooting

### Watch Not Connecting
- Ensure phone app is running
- Check Bluetooth connection between watch and phone
- Restart both apps

### Shutter Not Working
- Verify camera is in pairing mode
- Check phone app camera connection
- Ensure watch is connected to phone

### Performance Issues
- Close other apps on watch
- Ensure good Bluetooth signal strength
- Check watch battery level

## Future Enhancements

- **Multiple Camera Support**: Switch between different cameras
- **Settings Sync**: Sync camera settings between watch and phone
- **Voice Commands**: "Take a photo" voice trigger
- **Timer Mode**: Set countdown timer for photos
- **Burst Mode**: Take multiple photos in sequence
- **Preview Mode**: See camera preview on watch (if supported)