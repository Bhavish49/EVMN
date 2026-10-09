import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class DevelopmentToken {
  const DevelopmentToken({
    required this.id,
    required this.vehicleId,
    required this.purpose,
    required this.issuerId,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
  });

  final String id;
  final String vehicleId;
  final String purpose;
  final String issuerId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String signature;

  Map<String, Object> body() => {
    'id': id,
    'vehicleId': vehicleId,
    'purpose': purpose,
    'issuerId': issuerId,
    'issuedAt': issuedAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  String export() => jsonEncode({...body(), 'signature': signature});
}

/// In-memory simulator authority. Its private key is never serialized or sent.
class TokenService {
  TokenService();

  final Ed25519 _algorithm = Ed25519();
  late final Future<SimpleKeyPair> _keyPair = _algorithm.newKeyPair();
  static const issuer = 'EVMN-LOCAL-SIMULATOR';

  Future<DevelopmentToken> issue(
    String vehicleId, {
    Duration lifetime = const Duration(minutes: 15),
  }) async {
    final now = DateTime.now().toUtc();
    final keyPairData = await _keyPair;
    final tokenId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final unsigned = DevelopmentToken(
      id: tokenId,
      vehicleId: vehicleId.trim(),
      purpose: 'patient_transport',
      issuerId: issuer,
      issuedAt: now,
      expiresAt: now.add(lifetime),
      signature: '',
    );
    final signature = await _algorithm.sign(
      utf8.encode(jsonEncode(unsigned.body())),
      keyPair: keyPairData,
    );
    return DevelopmentToken(
      id: tokenId,
      vehicleId: unsigned.vehicleId,
      purpose: unsigned.purpose,
      issuerId: issuer,
      issuedAt: now,
      expiresAt: unsigned.expiresAt,
      signature: base64UrlEncode(signature.bytes),
    );
  }

  Future<bool> verify(
    DevelopmentToken token, {
    required String vehicleId,
  }) async {
    if (token.issuerId != issuer ||
        token.vehicleId != vehicleId.trim() ||
        token.purpose != 'patient_transport' ||
        !token.expiresAt.isAfter(DateTime.now().toUtc()) ||
        token.issuedAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        )) {
      return false;
    }
    final publicKey = await (await _keyPair).extractPublicKey();
    try {
      return await _algorithm.verify(
        utf8.encode(jsonEncode(token.body())),
        signature: Signature(
          base64Url.decode(base64Url.normalize(token.signature)),
          publicKey: publicKey,
        ),
      );
    } on Object {
      return false;
    }
  }
}
