import 'package:flutter_test/flutter_test.dart';
import 'package:emergency_vehicle_mesh_network/core/services/token_service.dart';

void main() {
  test('simulator issues a signed short-lived token for its vehicle', () async {
    final authority = TokenService();
    final token = await authority.issue('AMB-42');
    expect(await authority.verify(token, vehicleId: 'AMB-42'), isTrue);
    expect(await authority.verify(token, vehicleId: 'AMB-43'), isFalse);
  });

  test('rejects expired tokens and tokens from untrusted issuers', () async {
    final authority = TokenService();
    final expired = await authority.issue(
      'VAN-1',
      lifetime: const Duration(seconds: -1),
    );
    expect(await authority.verify(expired, vehicleId: 'VAN-1'), isFalse);
    final token = await authority.issue('VAN-1');
    final unknownIssuer = DevelopmentToken(
      id: token.id,
      vehicleId: token.vehicleId,
      purpose: token.purpose,
      issuerId: 'UNKNOWN',
      issuedAt: token.issuedAt,
      expiresAt: token.expiresAt,
      signature: token.signature,
    );
    expect(await authority.verify(unknownIssuer, vehicleId: 'VAN-1'), isFalse);
  });

  test('rejects modified signed token contents', () async {
    final authority = TokenService();
    final token = await authority.issue('CAR-9');
    final changed = DevelopmentToken(
      id: token.id,
      vehicleId: token.vehicleId,
      purpose: 'ambulance',
      issuerId: token.issuerId,
      issuedAt: token.issuedAt,
      expiresAt: token.expiresAt,
      signature: token.signature,
    );
    expect(await authority.verify(changed, vehicleId: 'CAR-9'), isFalse);
  });
}
