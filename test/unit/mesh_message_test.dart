import 'package:flutter_test/flutter_test.dart';
import 'package:emergency_vehicle_mesh_network/core/models/mesh_message.dart';
import 'package:emergency_vehicle_mesh_network/core/services/mesh_policy.dart';

void main() {
  group('MeshMessage', () {
    test('round-trips the compact BLE representation', () {
      final original = MeshMessage.create(EmergencyKind.ambulance);
      final decoded = MeshMessage.decode(original.encode());
      expect(decoded.id, original.id);
      expect(decoded.kind, original.kind);
      expect(decoded.ttl, original.ttl);
      expect(decoded.hopCount, 0);
      expect(decoded.expiresAt, original.expiresAt);
      expect(original.encode(), hasLength(MeshMessage.encodedLength));
    });


    test(
      'forwarding decrements TTL and increments hops without extending expiry',
      () {
        final original = MeshMessage.create(
          EmergencyKind.patientTransport,
          ttl: 2,
        );
        final forwarded = original.forwarded()!;
        expect(forwarded.id, original.id);
        expect(forwarded.ttl, 1);
        expect(forwarded.hopCount, 1);
        expect(forwarded.expiresAt, original.expiresAt);
        expect(forwarded.forwarded()!.ttl, 0);
        expect(forwarded.forwarded()!.forwarded(), isNull);
      },
    );

    test('rejects malformed, unsupported, and expired packets', () {
      expect(() => MeshMessage.decode([1, 1]), throwsFormatException);
      final packet = MeshMessage.create(EmergencyKind.ambulance).encode()
        ..[0] = 9;
      expect(() => MeshMessage.decode(packet), throwsFormatException);
      final invalidTtl = MeshMessage.create(EmergencyKind.ambulance).encode()
        ..[6] = 16;
      expect(() => MeshMessage.decode(invalidTtl), throwsFormatException);
      final tooLong = MeshMessage.create(EmergencyKind.ambulance).encode()
        ..[8] = 0xff
        ..[9] = 0xff;
      expect(() => MeshMessage.decode(tooLong), throwsFormatException);
      final expired = MeshMessage(
        id: '00112233',
        kind: EmergencyKind.ambulance,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 2)),
        ttl: 3,
        hopCount: 0,
      );
      expect(MeshMessage.decode(expired.encode()).isExpired, isTrue);
      expect(expired.forwarded(), isNull);
    });
  });

  test('bounded duplicate cache suppresses repeats and evicts old IDs', () {
    final cache = BoundedDedupCache(capacity: 2);
    expect(cache.recordIfNew('a'), isTrue);
    expect(cache.recordIfNew('a'), isFalse);
    cache.recordIfNew('b');
    cache.recordIfNew('c');
    expect(cache.length, 2);
    expect(cache.contains('a'), isFalse);
    expect(cache.recordIfNew('a'), isTrue);
  });

  test('forwarding rate limiter spaces transmissions', () {
    final limiter = ForwardingRateLimit(
      minimumInterval: const Duration(seconds: 1),
    );
    final now = DateTime.utc(2026, 1, 1);
    expect(limiter.allow(now: now), isTrue);
    expect(
      limiter.allow(now: now.add(const Duration(milliseconds: 999))),
      isFalse,
    );
    expect(limiter.allow(now: now.add(const Duration(seconds: 1))), isTrue);
  });
}
