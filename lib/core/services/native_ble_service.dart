import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class NativeBleService {
  static const _methods = MethodChannel('evmn/ble');
  static const _events = EventChannel('evmn/ble_events');

  bool get isNativeAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get isBlePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.windows);

  bool get isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  bool get supportsOfflineVoice => isNativeAndroid || isWindowsDesktop;

  Stream<Map<String, Object?>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, Object?>.from(event as Map));

  Future<bool> requestPermissions() async =>
      await _methods.invokeMethod<bool>('requestPermissions') ?? false;
  Future<bool> isSupported() async =>
      await _methods.invokeMethod<bool>('isSupported') ?? false;
  Future<bool> isBluetoothEnabled() async =>
      await _methods.invokeMethod<bool>('isBluetoothEnabled') ?? false;
  Future<bool> hasBlePermissions() async =>
      await _methods.invokeMethod<bool>('hasBlePermissions') ?? false;
  Future<void> startScan() => _methods.invokeMethod<void>('startScan');
  Future<void> stopScan() => _methods.invokeMethod<void>('stopScan');
  Future<void> startAdvertising(List<int> packet) =>
      _methods.invokeMethod<void>('startAdvertising', {'packet': packet});
  Future<void> stopAdvertising() =>
      _methods.invokeMethod<void>('stopAdvertising');
  Future<void> speak(String message) =>
      _methods.invokeMethod<void>('speak', {'message': message});
  Future<void> playAlertTone() =>
      _methods.invokeMethod<void>('playAlertTone');
  Future<bool> isTtsReady() async =>
      await _methods.invokeMethod<bool>('isTtsReady') ?? false;
}
