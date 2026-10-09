import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../models/mesh_message.dart';
import '../services/history_store.dart';
import '../services/mesh_policy.dart';
import '../services/native_ble_service.dart';
import '../services/token_service.dart';
import '../services/vehicle_profile_store.dart';

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppState {
  const AppState({
    this.role = 'Normal Vehicle',
    this.bleRuntime = false,
    this.scanning = false,
    this.drivingMode = false,
    this.advertising = false,
    this.bluetoothSupported = false,
    this.bluetoothPermissionsGranted = false,
    this.bluetoothEnabled = false,
    this.ttsReady = false,
    this.peers = 0,
    this.alerts = const [],
    this.events = const [],
    this.status = 'Checking Bluetooth readiness…',
    this.activeToken,
    this.vehicleId = '',
    this.vehicleType = 'Sedan',
    this.vehicleColor = '',
    this.plateNumber = '',
  });

  final String role;
  final bool bleRuntime;
  final bool scanning;
  final bool drivingMode;
  final bool advertising;
  final bool bluetoothSupported;
  final bool bluetoothPermissionsGranted;
  final bool bluetoothEnabled;
  final bool ttsReady;
  final int peers;
  final List<MeshMessage> alerts;
  final List<Map<String, Object?>> events;
  final String status;
  final DevelopmentToken? activeToken;
  final String vehicleId;
  final String vehicleType;
  final String vehicleColor;
  final String plateNumber;

  AppState copyWith({
    String? role,
    bool? bleRuntime,
    bool? scanning,
    bool? drivingMode,
    bool? advertising,
    bool? bluetoothSupported,
    bool? bluetoothPermissionsGranted,
    bool? bluetoothEnabled,
    bool? ttsReady,
    int? peers,
    List<MeshMessage>? alerts,
    List<Map<String, Object?>>? events,
    String? status,
    DevelopmentToken? activeToken,
    bool clearToken = false,
    String? vehicleId,
    String? vehicleType,
    String? vehicleColor,
    String? plateNumber,
  }) => AppState(
    role: role ?? this.role,
    bleRuntime: bleRuntime ?? this.bleRuntime,
    scanning: scanning ?? this.scanning,
    drivingMode: drivingMode ?? this.drivingMode,
    advertising: advertising ?? this.advertising,
    bluetoothSupported: bluetoothSupported ?? this.bluetoothSupported,
    bluetoothPermissionsGranted:
        bluetoothPermissionsGranted ?? this.bluetoothPermissionsGranted,
    bluetoothEnabled: bluetoothEnabled ?? this.bluetoothEnabled,
    ttsReady: ttsReady ?? this.ttsReady,
    peers: peers ?? this.peers,
    alerts: alerts ?? this.alerts,
    events: events ?? this.events,
    status: status ?? this.status,
    activeToken: clearToken ? null : activeToken ?? this.activeToken,
    vehicleId: vehicleId ?? this.vehicleId,
    vehicleType: vehicleType ?? this.vehicleType,
    vehicleColor: vehicleColor ?? this.vehicleColor,
    plateNumber: plateNumber ?? this.plateNumber,
  );
}

class AppController extends Notifier<AppState> {
  final NativeBleService _ble = NativeBleService();
  final HistoryStore _history = HistoryStore();
  final TokenService _tokens = TokenService();
  final VehicleProfileStore _vehicleProfiles = VehicleProfileStore();
  final BoundedDedupCache _seen = BoundedDedupCache();
  final ForwardingRateLimit _forwardRateLimit = ForwardingRateLimit();
  StreamSubscription<Map<String, Object?>>? _subscription;
  Timer? _emergencyRefreshTimer;

  @override
  AppState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _emergencyRefreshTimer?.cancel();
    });
    scheduleMicrotask(_initialize);
    return AppState(bleRuntime: _ble.isBlePlatform);
  }

  Future<void> _initialize() async {
    try {
      final profile = await _vehicleProfiles.read();
      state = state.copyWith(
        vehicleType: profile['type'] ?? state.vehicleType,
        vehicleColor: profile['color'] ?? state.vehicleColor,
        plateNumber: profile['plate'] ?? state.plateNumber,
      );
    } on Object catch (error) {
      state = state.copyWith(status: 'Could not load vehicle profile: $error');
    }
    if (!_ble.isBlePlatform) {
      state = state.copyWith(
        status:
            'BLE is available in this MVP on Android phones and Windows laptops.',
      );
      return;
    }
    try {
      var supported = await _ble.isSupported();
      // Windows initializes its radio asynchronously through WinRT. Give it a
      // short window to finish before reporting that BLE is unsupported.
      for (var attempt = 0; _ble.isWindowsDesktop && !supported && attempt < 8; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        supported = await _ble.isSupported();
      }
      final permissionsGranted = await _ble.hasBlePermissions();
      final enabled = await _ble.isBluetoothEnabled();
      final ttsReady = await _ble.isTtsReady();
      _subscription = _ble.events.listen(
        _onBleEvent,
        onError: (Object error) {
          state = state.copyWith(status: 'Bluetooth error: $error');
        },
      );
      state = state.copyWith(
        bluetoothSupported: supported,
        bluetoothPermissionsGranted: permissionsGranted,
        bluetoothEnabled: enabled,
        ttsReady: ttsReady,
        status: !supported
            ? 'BLE is unavailable on this device.'
            : !permissionsGranted
            ? 'Grant Nearby devices permission to use Bluetooth.'
            : enabled
            ? 'Ready to connect to nearby EVMN nodes.'
            : 'Bluetooth is turned off. Enable it in Android Quick Settings.',
      );
      await refreshHistory();
    } on PlatformException catch (error) {
      state = state.copyWith(
        status: 'Bluetooth setup failed: ${error.message ?? error.code}',
      );
    } catch (error) {
      state = state.copyWith(status: 'Bluetooth setup failed: $error');
    }
  }

  Future<void> requestPermissions() async {
    if (!_ble.isBlePlatform) {
      state = state.copyWith(
        status: 'BLE permission handling is available on Android and Windows.',
      );
      return;
    }
    final granted = await _ble.requestPermissions();
    final enabled = granted
        ? await _ble.isBluetoothEnabled()
        : state.bluetoothEnabled;
    state = state.copyWith(
      bluetoothPermissionsGranted: granted,
      bluetoothEnabled: enabled,
      status: granted
          ? enabled
                ? 'Bluetooth permissions granted.'
                : 'Bluetooth is off. Enable it in Android Quick Settings.'
          : 'Bluetooth permissions are required.',
    );
  }

  Future<void> toggleScan() async {
    if (!_ble.isBlePlatform) {
      state = state.copyWith(
        status:
            'BLE scanning requires an Android phone or Windows laptop.',
      );
      return;
    }
    try {
      if (state.scanning) {
        await _ble.stopScan();
        state = state.copyWith(scanning: false, status: 'Scanning stopped.');
      } else {
        await requestPermissions();
        await _ble.startScan();
        state = state.copyWith(
          scanning: true,
          status: 'Scanning for EVMN emergency broadcasts.',
        );
      }
    } on PlatformException catch (error) {
      state = state.copyWith(
        status: 'Could not change scan state: ${error.message ?? error.code}',
      );
    }
  }

  Future<void> setDrivingMode(bool enabled) async {
    if (!enabled) {
      try {
        _emergencyRefreshTimer?.cancel();
        _emergencyRefreshTimer = null;
        if (state.scanning) await _ble.stopScan();
        if (state.advertising) await _ble.stopAdvertising();
        state = state.copyWith(
          drivingMode: false,
          scanning: false,
          advertising: false,
          status: 'Driving Mode is off. Nearby scanning has stopped.',
        );
      } on PlatformException catch (error) {
        state = state.copyWith(
          drivingMode: false,
          scanning: false,
          status: 'Could not stop nearby scanning: ${error.message ?? error.code}',
        );
      }
      return;
    }

    if (!_ble.isBlePlatform) {
      state = state.copyWith(
        drivingMode: false,
        status: 'Nearby scanning requires an Android phone or Windows laptop.',
      );
      return;
    }

    try {
      final granted = await _ble.requestPermissions();
      final enabled = granted && await _ble.isBluetoothEnabled();
      state = state.copyWith(
        bluetoothPermissionsGranted: granted,
        bluetoothEnabled: enabled,
      );
      if (!granted || !enabled) {
        state = state.copyWith(
          drivingMode: false,
          scanning: false,
          status: !granted
              ? 'Nearby-device permission is required for Driving Mode.'
              : 'Turn on Bluetooth to use Driving Mode.',
        );
        return;
      }
      await _ble.startScan();
      state = state.copyWith(
        drivingMode: true,
        scanning: true,
        status: 'Driving Mode is on. Listening for nearby emergency alerts.',
      );
      if (state.role == 'Temporary Patient Transport' && state.activeToken != null) {
        await broadcastPatientTransport();
      } else if (state.vehicleType.toLowerCase() == 'ambulance') {
        await broadcast(EmergencyKind.ambulance);
      }
      if (_isEmergencyVehicle) {
        _emergencyRefreshTimer?.cancel();
        _emergencyRefreshTimer = Timer.periodic(const Duration(minutes: 4), (_) {
          unawaited(_refreshEmergencyBroadcast());
        });
      }
    } on PlatformException catch (error) {
      state = state.copyWith(
        drivingMode: false,
        scanning: false,
        status: 'Driving Mode could not start: ${error.message ?? error.code}',
      );
    }
  }

  bool get _isEmergencyVehicle =>
      state.vehicleType.toLowerCase() == 'ambulance' ||
      (state.role == 'Temporary Patient Transport' && state.activeToken != null);

  Future<void> _refreshEmergencyBroadcast() async {
    if (!state.drivingMode || !_isEmergencyVehicle) return;
    if (state.role == 'Temporary Patient Transport') {
      await broadcastPatientTransport();
    } else {
      await broadcast(EmergencyKind.ambulance);
    }
  }

  Future<void> broadcast(EmergencyKind kind) async {
    if (!_ble.isBlePlatform) {
      state = state.copyWith(
        status:
            'BLE broadcasting requires an Android phone or Windows laptop.',
      );
      return;
    }
    final message = MeshMessage.create(
      kind,
      vehicleColor: state.vehicleColor,
      plateNumber: state.plateNumber,
    );
    try {
      await requestPermissions();
      await _ble.startAdvertising(message.encode());
      _seen.recordIfNew(message.id);
      state = state.copyWith(
        advertising: true,
        alerts: [message, ...state.alerts],
        status:
            'Broadcasting ${kind == EmergencyKind.ambulance ? 'simulated ambulance' : 'patient transport'} alert.',
      );
      await _history.add(
        'sent',
        '${kind.name}; TTL ${message.ttl}; hop 0',
        messageId: message.id,
      );
      await refreshHistory();
    } on PlatformException catch (error) {
      state = state.copyWith(
        status: 'Broadcast failed: ${error.message ?? error.code}',
      );
    }
  }

  Future<void> saveVehicleProfile({required String type, required String color, required String plate}) async {
    final cleanedType = type.trim();
    final cleanedColor = color.trim();
    final cleanedPlate = plate.trim().toUpperCase().replaceAll(' ', '');
    if (cleanedPlate.length > 13 || !RegExp(r'^[A-Z0-9-]*$').hasMatch(cleanedPlate)) {
      state = state.copyWith(status: 'Use up to 13 letters, numbers, or hyphens for the number plate.');
      return;
    }
    try {
      await _vehicleProfiles.save(type: cleanedType, color: cleanedColor, plate: cleanedPlate);
      state = state.copyWith(vehicleType: cleanedType, vehicleColor: cleanedColor, plateNumber: cleanedPlate, status: 'Vehicle profile saved on this device.');
    } on Object catch (error) {
      state = state.copyWith(status: 'Could not save vehicle profile: $error');
    }
  }

  Future<void> stopAdvertising() async {
    if (!_ble.isBlePlatform) {
      state = state.copyWith(
        status:
            'BLE advertising requires an Android phone or Windows laptop.',
      );
      return;
    }
    await _ble.stopAdvertising();
    state = state.copyWith(
      advertising: false,
      status: 'Emergency broadcast ended.',
    );
  }

  Future<void> broadcastPatientTransport() async {
    final token = state.activeToken;
    if (state.role != 'Temporary Patient Transport' || token == null) {
      state = state.copyWith(
        status: 'A verified simulator token is required first.',
      );
      return;
    }
    if (!await _tokens.verify(token, vehicleId: state.vehicleId)) {
      _emergencyRefreshTimer?.cancel();
      if (state.advertising) await _ble.stopAdvertising();
      state = state.copyWith(
        clearToken: true,
        advertising: false,
        status:
            'The simulator token expired or no longer matches this vehicle.',
      );
      await _history.add(
        'token_expired',
        'Token ${token.id} rejected at use time.',
        messageId: token.id,
      );
      await refreshHistory();
      return;
    }
    await broadcast(EmergencyKind.patientTransport);
  }

  Future<void> activateTemporaryEmergency() async {
    if (state.plateNumber.isEmpty) {
      state = state.copyWith(
        status: 'Save your vehicle colour and number plate in Profile first.',
      );
      return;
    }
    final authorized = await authorizePatientTransport(state.plateNumber);
    if (!authorized) return;
    await setDrivingMode(true);
  }

  Future<void> deactivateTemporaryEmergency() async {
    _emergencyRefreshTimer?.cancel();
    _emergencyRefreshTimer = null;
    try {
      if (state.vehicleType.toLowerCase() != 'ambulance' && state.advertising) {
        await _ble.stopAdvertising();
      }
      state = state.copyWith(
        role: 'Normal Vehicle',
        clearToken: true,
        advertising: state.vehicleType.toLowerCase() == 'ambulance'
            ? state.advertising
            : false,
        status: 'Temporary emergency mode ended.',
      );
      await _history.add('role', 'Temporary emergency mode ended.');
      await refreshHistory();
    } on PlatformException catch (error) {
      state = state.copyWith(
        status: 'Could not end temporary emergency mode: ${error.message ?? error.code}',
      );
    }
  }

  Future<void> setRole(String role) async {
    state = state.copyWith(
      role: role,
      clearToken: role != 'Temporary Patient Transport',
    );
    await _history.add('role', 'Role changed to $role');
    await refreshHistory();
  }

  Future<bool> authorizePatientTransport(String vehicleId) async {
    final cleaned = vehicleId.trim();
    if (cleaned.isEmpty) {
      state = state.copyWith(status: 'Enter a vehicle identifier first.');
      return false;
    }
    final token = await _tokens.issue(cleaned);
    final valid = await _tokens.verify(token, vehicleId: cleaned);
    if (!valid) {
      state = state.copyWith(status: 'Development token verification failed.');
      return false;
    }
    state = state.copyWith(
      role: 'Temporary Patient Transport',
      vehicleId: cleaned,
      activeToken: token,
      status: 'Simulator token valid until ${token.expiresAt.toLocal()}.',
    );
    await _history.add(
      'token_issued',
      'Simulator token ${token.id} for $cleaned expires ${token.expiresAt.toIso8601String()}',
    );
    await refreshHistory();
    return true;
  }

  Future<void> announceTest() async {
    if (!_ble.supportsOfflineVoice) {
      state = state.copyWith(
        status:
            'Offline Android voice alerts require an Android phone or emulator.',
      );
      return;
    }
    try {
      await _ble.speak(
        'EVMN offline voice test. Emergency vehicle alert. Give way safely when appropriate.',
      );
      state = state.copyWith(
        status: state.ttsReady
            ? 'Offline voice test sent.'
            : 'Voice service unavailable; visual alerts remain enabled.',
      );
    } on PlatformException catch (error) {
      state = state.copyWith(
        status: 'Voice alert unavailable: ${error.message ?? error.code}',
      );
    }
  }

  Future<void> refreshHistory() async {
    try {
      state = state.copyWith(events: await _history.recent());
    } catch (_) {
      state = state.copyWith(
        status: 'Local history database could not be opened.',
      );
    }
  }

  void _onBleEvent(Map<String, Object?> event) {
    if (event['type'] == 'error') {
      state = state.copyWith(status: 'Bluetooth error: ${event['message']}');
      return;
    }
    if (event['type'] == 'tts') {
      state = state.copyWith(ttsReady: event['ready'] == true);
      return;
    }
    if (event['type'] == 'peer') {
      state = state.copyWith(
        peers: (event['count'] as int?) ?? state.peers + 1,
      );
      return;
    }
    if (event['type'] != 'packet') return;
    try {
      final message = MeshMessage.decode(
        List<int>.from(event['packet'] as List),
      );
      if (!_seen.recordIfNew(message.id)) {
        unawaited(
          _history
              .add(
                'duplicate',
                'Duplicate packet ignored.',
                messageId: message.id,
              )
              .then((_) => refreshHistory()),
        );
        return;
      }
      if (message.isExpired) {
        unawaited(
          _history
              .add('expired', 'Expired message ignored.', messageId: message.id)
              .then((_) => refreshHistory()),
        );
        return;
      }
      state = state.copyWith(
        alerts: [message, ...state.alerts],
        status: 'Received ${message.kind.name} alert from nearby node.',
      );
      final vehicleDescription = [
        if (message.vehicleColor != 'Other') message.vehicleColor,
        if (message.plateNumber.isNotEmpty) 'vehicle ${message.plateNumber}',
      ].where((part) => part.isNotEmpty).join(' ');
      final phrase = message.kind == EmergencyKind.ambulance
          ? 'Ambulance approaching. Please give way safely.'
          : vehicleDescription.isEmpty
          ? 'Emergency patient transport alert. Please give way safely.'
          : '$vehicleDescription is in an emergency. Please give way safely.';
      if (_ble.supportsOfflineVoice) unawaited(_announceEmergency(phrase));
      unawaited(
        _history
            .add(
              'received',
              '${message.kind.name}; TTL ${message.ttl}; hop ${message.hopCount}',
              messageId: message.id,
            )
            .then((_) => refreshHistory()),
      );
      final forwarded = message.forwarded();
      if (forwarded != null && _forwardRateLimit.allow()) {
        unawaited(
          Future<void>.delayed(
            Duration(milliseconds: 350 + (message.id.hashCode.abs() % 1100)),
            () async {
              try {
                await _ble.startAdvertising(forwarded.encode());
                state = state.copyWith(
                  advertising: true,
                  status:
                      'Forwarding alert with TTL ${forwarded.ttl}, hop ${forwarded.hopCount}.',
                );
                await _history.add(
                  'forwarded',
                  'TTL ${forwarded.ttl}; hop ${forwarded.hopCount}',
                  messageId: forwarded.id,
                );
                await refreshHistory();
                await Future<void>.delayed(const Duration(seconds: 4));
                if (state.role != 'Ambulance / Emergency Vehicle' &&
                    state.role != 'Temporary Patient Transport') {
                  await _ble.stopAdvertising();
                  state = state.copyWith(advertising: false);
                }
              } on PlatformException catch (error) {
                state = state.copyWith(
                  status: 'Forwarding failed: ${error.message ?? error.code}',
                );
              }
            },
          ),
        );
      }
    } on Object catch (error) {
      unawaited(
        _history
            .add('rejected', 'Malformed BLE packet: $error')
            .then((_) => refreshHistory()),
      );
    }
  }

  Future<void> _announceEmergency(String phrase) async {
    try {
      await _ble.playAlertTone();
      await Future<void>.delayed(const Duration(seconds: 1));
      await _ble.speak(phrase);
    } on PlatformException catch (error) {
      state = state.copyWith(
        status: 'Offline voice alert unavailable: ${error.message ?? error.code}',
      );
    }
  }
}
