# Canon Camera Remote Control App

A Flutter Android application that allows you to control your Canon camera shutter wirelessly using Bluetooth Low Energy (BLE).

## Features

- **Device Discovery**: Scan for and select your Canon camera from available BLE devices
- **Camera Pairing**: Automatically pair with your camera using the device name
- **Remote Shutter Control**: Trigger camera shutter with a beautiful animated button
- **Persistent Storage**: Remember your camera for future connections
- **Modern Dark Mode UI**: Clean, modern interface optimized for photography workflows
- **Connection Status**: Real-time connection status indicators

## How It Works

The app communicates with your Canon camera using BLE GATT services, similar to the Python script in the `python-test` directory. It:

1. **Scans** for available BLE devices
2. **Connects** to your selected Canon camera
3. **Pairs** by sending the device name (e.g., "ANDROID") to handle `0x0017`
4. **Controls** the shutter by sending commands to handle `0x0019`

## Setup

### Prerequisites

- Android device with Bluetooth Low Energy support
- Canon camera with BLE capabilities
- Flutter development environment

### Installation

1. Clone this repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Connect your Android device or start an emulator
4. Run the app:
   ```bash
   flutter run
   ```

### Permissions

The app automatically requests the following permissions:
- Bluetooth Connect
- Bluetooth Scan
- Location (required for BLE scanning on Android)

## Usage

1. **Launch the app** - You'll see a splash screen with the app logo
2. **Scan for cameras** - Tap "Scan for Cameras" to discover available devices
3. **Select your camera** - Choose your Canon camera from the list
4. **Automatic pairing** - The app will connect and pair with your camera
5. **Take photos** - Use the large shutter button to capture photos remotely

## Technical Details

### BLE Communication

The app uses the following GATT characteristics:
- **0x0017**: Pairing handle - sends device name for authentication
- **0x0019**: Shutter control - sends button commands

### Button Commands

- `BUTTON_RELEASE | IMMEDIATE` (0b10001100): Triggers immediate shutter release

### Architecture

- **CameraBLEService**: Handles all BLE communication and camera control
- **DeviceSelectionScreen**: Device discovery and selection interface
- **CameraControlScreen**: Main camera control interface with shutter button
- **SharedPreferences**: Persistent storage for camera address and name

## Troubleshooting

### Camera Not Found
- Ensure your camera's Bluetooth is enabled
- Make sure the camera is in pairing mode
- Try restarting the scan

### Connection Issues
- Check that Bluetooth is enabled on your Android device
- Ensure location services are enabled (required for BLE scanning)
- Try disconnecting and reconnecting

### Shutter Not Working
- Verify the camera is in the correct shooting mode
- Check that the camera supports remote shutter control
- Ensure the app has successfully paired with the camera

## Development

This app is built with Flutter and uses the following packages:
- `flutter_blue_plus`: BLE communication
- `shared_preferences`: Local storage
- `permission_handler`: Android permissions

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
