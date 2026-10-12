# Emergency Vehicle Mesh Network (EVMN)

EVMN is an offline-first Flutter prototype that exchanges emergency-awareness alerts between nearby Android phones and Windows computers over Bluetooth Low Energy (BLE). It is a demonstration project, not an emergency service or a certified vehicle warning system.

## What it does

- Stores the vehicle type, colour, and plate locally on the device.
- Provides a simple Driving Mode that listens for nearby EVMN alerts.
- Automatically broadcasts while Driving Mode is active for an ambulance profile or an activated temporary emergency vehicle.
- Sends the emergency type, a short-lived message ID, expiry, forwarding limits, and compact vehicle colour/plate details in a 24-byte BLE manufacturer-data message. Receives older 10-byte messages as generic alerts.
- Plays a brief two-beep attention cue, waits one second, then uses installed offline speech to announce the alert on Android and Windows.
- Deduplicates, expires, and relays eligible alerts while Driving Mode is enabled.
- Keeps a local event history. It does not use a server or account.

## Requirements

- Flutter and Dart versions compatible with `pubspec.yaml`.
- Android Studio/Android SDK for Android builds.
- Visual Studio with the Desktop development with C++ workload for Windows builds.
- BLE-capable hardware for nearby-device testing.
- An installed offline text-to-speech voice on the device for spoken alerts.

## Run

### Download for Android

Download the latest Android APK directly from [GitHub Releases](https://github.com/Bhavish49/EVMN/releases/latest/download/app-release.apk). If no APK is available yet, build one locally with `flutter build apk --release`; it is created at `build/app/outputs/flutter-apk/app-release.apk`.

Fetch Flutter dependencies, then launch on a supported target:

```powershell
flutter pub get
flutter devices
flutter run -d windows
```

For Android, connect a BLE-capable phone with USB debugging enabled and run:

```powershell
flutter run -d <android-device-id>
```

Grant nearby-device permissions and enable Bluetooth. On Home, turn on Driving Mode. A normal vehicle listens for alerts; an ambulance profile or an activated temporary emergency vehicle also broadcasts while Driving Mode is on. On Android, Driving Mode runs in a foreground service with an ongoing notification, so BLE listening, emergency broadcasts, alert forwarding, and offline voice can continue when the screen is locked or the app is dismissed from Recents. Turn Driving Mode off in the app or use the notification's **Turn off** action. Android may stop background work if the user force-stops the app, disables Bluetooth, revokes permissions, or the device restricts background activity. Windows continues while the app is minimized, but closing the Windows app ends its process and BLE work.

Windows speech uses the installed Windows SAPI voice. Android speech uses Android TextToSpeech and requires offline voice data for offline operation. BLE support is implemented for Android and Windows; web, iOS, Linux, and macOS are not supported by the current BLE implementation.

## Development

The Flutter UI and application state are in `lib/`. The mesh packet model and forwarding policy are in `lib/core/`. Android BLE and offline speech use the platform channel in `android/app/src/main/kotlin/`. Windows BLE and offline speech use the native runner in `windows/runner/`.

Useful commands:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows
```

## Safety and prototype limitations

- BLE alerts are unauthenticated and can be spoofed. Do not rely on them for emergency response or make sudden driving decisions based on an alert.
- BLE advertisements are connectionless and delivery is not guaranteed. Android background operation uses a foreground service and visible ongoing notification; it is not a guarantee against force-stop, radio shutdown, or manufacturer-specific battery restrictions. Windows has no separate background service when its app process is closed.
- Temporary emergency authorization is a local development-token simulation, not approval from an emergency authority. Its signing key is held in memory and does not establish trust between separate devices.
- The Bluetooth manufacturer identifier `0xFFFF` is reserved for internal testing. This prototype must remain a controlled demonstration and should not be deployed as a public safety service.
- Vehicle details are carried in an unsigned packet. Do not include information that should remain private.
- The project does not contact emergency services or grant traffic priority.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for the contribution workflow and project expectations.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
