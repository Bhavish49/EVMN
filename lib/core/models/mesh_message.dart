import 'dart:math';

enum EmergencyKind { ambulance, patientTransport }

class MeshMessage {
  const MeshMessage({
    required this.id,
    required this.kind,
    required this.expiresAt,
    required this.ttl,
    required this.hopCount,
    this.vehicleColor = '',
    this.plateNumber = '',
  });

  static const protocolVersion = 2;
  static const legacyProtocolVersion = 1;
  static const legacyEncodedLength = 10;
  static const encodedLength = 24;
  static const vehicleColors = <String>[
    'Black', 'White', 'Silver', 'Gray', 'Red', 'Blue', 'Green', 'Yellow',
    'Brown', 'Beige', 'Orange', 'Purple', 'Gold', 'Maroon', 'Navy', 'Other',
  ];

  final String id;
  final EmergencyKind kind;
  final DateTime expiresAt;
  final int ttl;
  final int hopCount;
  final String vehicleColor;
  final String plateNumber;

  factory MeshMessage.create(
    EmergencyKind kind, {
    int ttl = 4,
    String vehicleColor = '',
    String plateNumber = '',
  }) {
    final random = Random.secure();
    final id = List.generate(
      4,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final proposedExpiry = DateTime.now().toUtc().add(
      const Duration(minutes: 5),
    );
    return MeshMessage(
      id: id,
      kind: kind,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        proposedExpiry.millisecondsSinceEpoch ~/ 60000 * 60000,
        isUtc: true,
      ),
      ttl: ttl,
      hopCount: 0,
      vehicleColor: vehicleColor,
      plateNumber: plateNumber,
    );
  }

  List<int> encode() {
    if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(id) ||
        ttl < 0 ||
        ttl > 15 ||
        hopCount < 0 ||
        hopCount > 15) {
      throw const FormatException('Invalid mesh message fields.');
    }
    final colorIndex = vehicleColors.indexOf(vehicleColor);
    final normalizedPlate = plateNumber.toUpperCase().replaceAll(' ', '');
    if (normalizedPlate.length > 13 || !RegExp(r'^[A-Z0-9-]*$').hasMatch(normalizedPlate)) {
      throw const FormatException('Number plate must be at most 13 letters or digits.');
    }
    final expiryMinute = expiresAt.toUtc().millisecondsSinceEpoch ~/ 60000;
    if (expiryMinute < 0) {
      throw const FormatException('Expiration timestamp is out of range.');
    }
    final idBytes = List.generate(
      4,
      (index) => int.parse(id.substring(index * 2, index * 2 + 2), radix: 16),
    );
    final packet = <int>[
      protocolVersion,
      kind.index + 1,
      ...idBytes,
      ttl,
      hopCount,
      (expiryMinute >> 8) & 255,
      expiryMinute & 255,
    ];
    packet.add((colorIndex < 0 ? vehicleColors.length - 1 : colorIndex) << 4 | normalizedPlate.length);
    packet.addAll(normalizedPlate.codeUnits);
    packet.addAll(List<int>.filled(13 - normalizedPlate.length, 0));
    return packet;
  }

  factory MeshMessage.decode(List<int> bytes) {
    if ((bytes.length != legacyEncodedLength && bytes.length != encodedLength) ||
        bytes.any((value) => value < 0 || value > 255)) {
      throw const FormatException('Malformed mesh packet.');
    }
    final isLegacy = bytes.length == legacyEncodedLength && bytes[0] == legacyProtocolVersion;
    if ((!isLegacy && (bytes.length != encodedLength || bytes[0] != protocolVersion)) ||
        bytes[1] < 1 ||
        bytes[1] > 2 ||
        bytes[6] > 15 ||
        bytes[7] > 15) {
      throw const FormatException('Unsupported protocol or message type.');
    }
    final id = bytes
        .sublist(2, 6)
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    final currentMinute =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ 60000;
    final encodedMinute = (bytes[8] << 8) | bytes[9];
    final minuteDelta =
        ((encodedMinute - (currentMinute & 0xffff) + 0x8000) & 0xffff) - 0x8000;
    if (minuteDelta > 5) {
      throw const FormatException(
        'Message expiration exceeds the protocol limit.',
      );
    }
    final expiryMinute = currentMinute + minuteDelta;
    var vehicleColor = '';
    var plateNumber = '';
    if (!isLegacy) {
      final metadata = bytes[10];
      final colorIndex = metadata >> 4;
      final plateLength = metadata & 0x0f;
      if (colorIndex >= vehicleColors.length || plateLength > 13) {
        throw const FormatException('Invalid vehicle details in emergency packet.');
      }
      vehicleColor = vehicleColors[colorIndex];
      plateNumber = String.fromCharCodes(bytes.sublist(11, 11 + plateLength));
    }
    return MeshMessage(
      id: id,
      kind: EmergencyKind.values[bytes[1] - 1],
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiryMinute * 60000,
        isUtc: true,
      ),
      ttl: bytes[6],
      hopCount: bytes[7],
      vehicleColor: vehicleColor,
      plateNumber: plateNumber,
    );
  }

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());

  MeshMessage? forwarded() {
    if (ttl == 0 || isExpired || hopCount >= 15) return null;
    return MeshMessage(
      id: id,
      kind: kind,
      expiresAt: expiresAt,
      ttl: ttl - 1,
      hopCount: hopCount + 1,
      vehicleColor: vehicleColor,
      plateNumber: plateNumber,
    );
  }
}
