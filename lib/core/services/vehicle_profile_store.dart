import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

class VehicleProfileStore {
  static const _channel = MethodChannel('evmn/ble');
  static const _fileName = 'vehicle_profile.json';

  Future<Map<String, String>> read() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final profile = await _channel.invokeMapMethod<String, String>('readVehicleProfile');
      return {
        'type': profile?['type'] ?? 'Sedan',
        'color': profile?['color'] ?? '',
        'plate': profile?['plate'] ?? '',
      };
    }

    final file = await _profileFile();
    if (!await file.exists()) return _emptyProfile();
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return _emptyProfile();
    return {
      'type': decoded['type'] is String ? decoded['type'] as String : 'Sedan',
      'color': decoded['color'] is String ? decoded['color'] as String : '',
      'plate': decoded['plate'] is String ? decoded['plate'] as String : '',
    };
  }

  Future<void> save({required String type, required String color, required String plate}) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _channel.invokeMethod<void>('saveVehicleProfile', {
        'type': type,
        'color': color,
        'plate': plate,
      });
      return;
    }

    final file = await _profileFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'type': type, 'color': color, 'plate': plate}));
  }

  Future<File> _profileFile() async {
    final base = Platform.isWindows
        ? Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path
        : Platform.environment['HOME'] ?? Directory.current.path;
    return File(p.join(base, '.evmn', _fileName));
  }

  Map<String, String> _emptyProfile() => {
    'type': 'Sedan',
    'color': '',
    'plate': '',
  };
}
