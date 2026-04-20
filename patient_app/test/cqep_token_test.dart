import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/core/encryption_service.dart';

void main() {
  test('CQEP token verifies before expiry', () {
    final token = EncryptionService.generateSecureToken(
      type: 'record',
      sessionId: 'session-1',
      uid: 'patient-1',
      expiry: DateTime.now().add(const Duration(seconds: 60)),
      nonce: EncryptionService.generateNonce(),
    );

    expect(EncryptionService.verifyToken(token), isTrue);
  });

  test('CQEP token rejects expired tokens', () {
    final token = EncryptionService.generateSecureToken(
      type: 'record',
      sessionId: 'session-1',
      uid: 'patient-1',
      expiry: DateTime.now().subtract(const Duration(seconds: 1)),
      nonce: EncryptionService.generateNonce(),
    );

    expect(EncryptionService.verifyToken(token), isFalse);
  });
}
